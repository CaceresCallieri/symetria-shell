# Investigation: clipboard-image-decode

**Started**: 2026-03-08
**Status**: Finalized

---

## Pass 1

**Timestamp**: 2026-03-08
**Status**: resolved

### Findings

- **152 images decoded when only 12 displayed**: `Clipboard.qml` `Qt.callLater` loop at line ~188 iterated ALL image entries, not just the first `maxImagesDisplayed` (12). Config at `config/ClipboardConfig.qml:8` sets `maxImagesDisplayed: 12`.
- **Truncated PNGs are the root cause**: 5 of 12 cached images had valid PNG headers (IHDR) but **no IEND terminator**. These are Wayland clipboard truncation artifacts — when the source app closes before `wl-paste --watch cliphist store` finishes reading, partial data is stored in cliphist's bolt DB.
- **Truncated files have exact-KiB sizes**: 65536 (64K), 106496 (104K), 131072 (128K), 2449408 (2392K) — matching what `cliphist list` reports. Complete PNGs have non-round sizes (66982, 161636, 642245, etc.).
- **IEND check confirms**: `tail -c 8 <file> | od` showed truncated files end with random IDAT data bytes, not the IEND marker `49454e44ae426082`.
- **PIL salvages truncated PNGs**: `PIL.ImageFile.LOAD_TRUNCATED_IMAGES = True` + `img.load()` + `img.save()` produces complete, valid PNGs with IEND. Fills missing data (shows as black regions at bottom of image).
- **ffmpeg and ImageMagick cannot salvage**: Both fail on the truncated IDAT/zlib streams. Only PIL's forgiving mode works.
- **`parent` reference error in StdioCollector**: `parent.decodedSize` inside a non-visual `StdioCollector` produces `ReferenceError: parent is not defined` at `Clipboard.qml:259`. Must use the Process's `id` instead (e.g., `decodeProcess.decodedSize`).
- **Qt Image `cache: true` (default) persists failed loads**: Once Qt caches a failed decode, subsequent renders of the same URL fail from cache even if the file is fixed. `cache: false` forces re-read from disk.

### Hypotheses

| # | Hypothesis | Confidence | Evidence |
|---|-----------|------------|----------|
| 1 | Truncated PNGs from Wayland clipboard | **CONFIRMED** | IEND missing on failing files, PIL salvage works, `file` shows valid headers |

### Eliminated

- **Race condition (concurrent decode processes)**: Eliminated because errors persist even with max 3 concurrent decodes. The same files always fail regardless of concurrency level. Files have valid headers + exact sizes matching cliphist metadata — they were stored truncated, not corrupted during decode.
- **Non-atomic file writes**: Eliminated because after switching to `> .tmp && mv .tmp .png`, errors continued with "Error decoding" (file exists but bad data), not "Cannot open" (file missing). The data itself is bad, not the write timing.
- **Cache deletion race (rm -rf during render)**: Eliminated as sole cause because errors occur on fresh shell launch (first-ever refresh, no prior cache to delete). Original theory was correct for the "Cannot open" variant but not for "Error decoding".
- **cliphist bolt DB concurrent access corruption**: Eliminated because even with 3 concurrent decodes (down from 152), same files fail. Manual `cliphist decode <id>` produces identical truncated data. The corruption is in stored data, not read-time.

### Code Paths

| File | Lines | Role |
|------|-------|------|
| `services/Clipboard.qml` | 30-101 | Refresh, decode queue, process management |
| `services/Clipboard.qml` | 242-286 | `decodeComponent` — spawns decode script, captures stdout/stderr, sets `imagePath` |
| `modules/clipboard/ImageGridItem.qml` | 61-88 | `Image` component that loads cached thumbnails, `onStatusChanged` diagnostics |
| `modules/clipboard/ClipboardItem.qml` | 77-98 | Image in text-tab list items (same loading pattern) |
| `modules/clipboard/Content.qml` | 64-66 | `imageEntries` computed property — filters to first 12 image entries |
| `config/ClipboardConfig.qml` | 8 | `maxImagesDisplayed: 12` |
| `scripts/cliphist-decode-image.sh` | 1-52 | **New** — decode + PIL repair + resize + atomic write pipeline |
| `utils/Paths.qml` | 21 | `clipboardcache` path definition |

### Errors & Symptoms

```
libpng error: Read Error
WARN scene: QML QQuickImage at @modules/clipboard/ImageGridItem.qml[61:9]: Error decoding: file:///home/jc/.cache/symmetria/imagecache/clipboard/5234.png: Unable to read image data
```

Also observed (from cache deletion race, fixed separately):
```
WARN scene: QML QQuickImage at @modules/clipboard/ImageGridItem.qml[61:9]: Cannot open: file:///home/jc/.cache/symmetria/imagecache/clipboard/5227.png
```

Reproduction: Open clipboard drawer → Images tab. Any entry stored from a clipboard source that closed before full transfer completes will show as blank/error.

### Changes Applied

| File | Change |
|------|--------|
| `services/Clipboard.qml` | Sequential decode queue (max 3 concurrent), only decode first `maxImagesDisplayed` images, pre-clear imagePaths before cache nuke, use decode script via `_decodeScript` property, fix `parent` → `decodeProcess` id reference |
| `modules/clipboard/ImageGridItem.qml` | `cache: false` on Image, `onStatusChanged` diagnostic logging |
| `modules/clipboard/ClipboardItem.qml` | `cache: false` on Image |
| `scripts/cliphist-decode-image.sh` | **New file** — full pipeline: `cliphist decode` → PIL `LOAD_TRUNCATED_IMAGES` repair → `img.thumbnail(512x512)` resize → `img.save(format=PNG)` → atomic `mv` |

### Next Steps

- [ ] **Restart shell and verify fix**: All 12 images should load — logs should show `[Clipboard] decode XXXX: OK size=NNNB` for all entries, no `LOAD FAILED` messages
- [ ] **Verify truncated images render**: Previously-failing entries (5232, 5234, 5242) should now show with partial content (black fill at bottom where data was missing)
- [ ] **Remove diagnostic logging**: Once confirmed working, strip `onStatusChanged` handlers and verbose `console.debug` lines from `Clipboard.qml` and `ImageGridItem.qml`
- [ ] **Consider CLAUDE.md update**: Document the truncated PNG pattern and PIL repair approach for future reference
- [ ] **Commit changes**: 4 files modified, 1 new file — conventional commit with scope `fix(clipboard)`

### Open Questions

- Should we show a visual indicator (e.g., subtle icon overlay) on images that were repaired from truncated data?
- Should `python-pillow` be listed as a dependency in the project, or is the fallback to raw copy sufficient?
- The `_maxConcurrentDecodes: 3` limit is conservative — could increase to 5-6 for faster loading once PIL handles all corruption cases

---

## Pass 2

**Timestamp**: 2026-03-09
**Status**: testing-fix

### Findings

- **PIL salvage produces black-filled images**: Truncated PNGs repaired with `LOAD_TRUNCATED_IMAGES = True` render with large black regions where data was missing. Users see these as broken duplicates of valid screenshots. Decision: **skip truncated images entirely** rather than salvage them.
- **Truncated detection via strict PIL load**: Removing `LOAD_TRUNCATED_IMAGES = True` and calling `img.load()` raises an exception on truncated PNGs. Script now exits with code 2 (truncated) vs 0 (success) vs 1 (error), allowing QML to differentiate.
- **GridView flicker root cause — JS array model identity**: QML `GridView` treats a plain JS array as an opaque model. When the array **reference** changes (even if contents are identical + 1 new item), GridView **destroys ALL delegates** and recreates them. This happens because `.filter()` always returns a new array.
- **Reactive binding creates N² re-renders**: The original `imageEntries` binding (`Clipboard.entries.filter(e => e.imagePath !== "")`) re-evaluated on every `imagePath` change (12+ valid decodes) AND every `skipped` change (8+ truncated). Each re-evaluation → new array → full delegate rebuild → all images reload. With 20 model changes × 12 delegates = ~240 unnecessary image loads.
- **`cache: true` alone does NOT fix flicker**: Even with Qt's in-memory image cache, delegate destruction/recreation takes at least one frame, producing a visible flash. The pixels load instantly from cache but the QML item lifecycle (destroy → create → layout → render) still causes a visual gap.
- **Backfill mechanism works**: When truncated images are skipped (exit code 2), `_backfillFromPool()` pulls the next undecoded image from `_imagePool` (remaining images beyond the initial `maxImagesDisplayed` batch). This ensures the grid fills to 12 even with high truncation rates. Logs confirm: 8 truncated entries skipped, 12 valid images decoded from a pool of 20.
- **Batch model update eliminates flicker**: Instead of a reactive binding, `decodedImageEntries` is set **once** via `_flushIfComplete()` when `_activeDecodes === 0 && _decodeQueue.length === 0`. The model goes from `[]` → `[12 entries]` in a single assignment. GridView creates all 12 delegates once.

### Hypotheses

| # | Hypothesis | Confidence | Evidence |
|---|-----------|------------|----------|
| 1 | JS array model reference change causes full delegate rebuild | **CONFIRMED** | Logs show ALL images reloading after each single decode completion. Removing reactive binding and using batch update should eliminate this. |
| 2 | Batch model update will eliminate flicker | HIGH | `_flushIfComplete()` sets model exactly once. GridView sees one change, creates delegates once. **Awaiting user verification.** |

### Eliminated

- **`cache: false` causing reloads**: Initially added `cache: false` to prevent Qt from caching failed loads. But with the new pipeline (only valid images reach the grid), `cache: true` is safe. Changed back to `cache: true`. However, `cache: true` alone didn't fix flicker — the delegate lifecycle itself causes the visual gap.
- **Progressive loading with `imagePath !== ""` filter**: Attempted filtering `imageEntries` on `e.imagePath !== ""` (grid grows as decodes complete, never shrinks). Still flickered because each valid decode changed the model reference, causing full rebuild.

### Code Paths

| File | Lines | Role |
|------|-------|------|
| `services/Clipboard.qml` | 34-51 | `refresh()` — clears `decodedImageEntries`, resets image paths, aborts queue |
| `services/Clipboard.qml` | 71-131 | Decode queue: `_maxConcurrentDecodes`, `_decodeQueue`, `_imagePool`, `_backfillFromPool()`, `_flushIfComplete()` |
| `services/Clipboard.qml` | 81-84 | `decodedImageEntries` — batch model, set once when all decodes complete |
| `services/Clipboard.qml` | 114-121 | `_flushIfComplete()` — checks queue empty + no active → filters + assigns model |
| `services/Clipboard.qml` | 274-326 | `decodeComponent` — exit code handling: 0=OK, 2=truncated+backfill, 1=fail+backfill |
| `scripts/cliphist-decode-image.sh` | 1-63 | Decode script: strict PIL load (no `LOAD_TRUNCATED_IMAGES`), exits 2 on truncated |
| `modules/clipboard/Content.qml` | 63-65 | `imageEntries` now reads `Clipboard.decodedImageEntries` (no reactive filter) |
| `modules/clipboard/ImageGridItem.qml` | 60-78 | Image with `cache: true`, diagnostic `onStatusChanged` removed |
| `modules/clipboard/ClipboardItem.qml` | 77-98 | Image with `cache: true` |

### Changes Applied

| File | Change |
|------|--------|
| `services/Clipboard.qml` | Added `decodedImageEntries` batch model, `_flushIfComplete()`, `_imagePool` for backfill, `_backfillFromPool()`, `_validDecodes` counter, `skipped` property on `ClipboardEntry`. Refresh clears `decodedImageEntries`. `onExited` calls `_flushIfComplete()` after queue processing. |
| `scripts/cliphist-decode-image.sh` | Changed from PIL `LOAD_TRUNCATED_IMAGES` repair to strict validation. Truncated images exit 2 (skip) instead of being salvaged with black fill. |
| `modules/clipboard/Content.qml` | `imageEntries` changed from reactive `.filter()` binding to direct reference to `Clipboard.decodedImageEntries`. |
| `modules/clipboard/ImageGridItem.qml` | `cache: true` restored, `onStatusChanged` diagnostic handler removed. |
| `modules/clipboard/ClipboardItem.qml` | `cache: true` restored. |

### Next Steps

- [ ] **Restart shell and verify flicker fix**: Open clipboard → Images tab. All 12 images should appear simultaneously with no flickering. Logs should show `all decodes complete: 12 images ready` exactly once.
- [ ] **Verify truncated entries are hidden**: Grid should only show valid screenshots. No black-filled images, no permanent loading icons.
- [ ] **Remove remaining diagnostic logging**: Strip `console.debug` lines from `Clipboard.qml` once verified. Keep `console.warn` for truncated/failed entries.
- [ ] **Investigate truncation source**: Determine if the truncation comes from `grim` screenshots, `wl-copy`, or `wl-paste --watch cliphist store`. Check if a timing fix on the capture side would prevent partial storage.
- [ ] **Commit changes**: 5 files modified, 1 new file — conventional commit `fix(clipboard): handle truncated clipboard images and eliminate grid flicker`
- [ ] **Consider CLAUDE.md update**: Document the JS array model flicker pattern and batch update solution.

### Open Questions

- Should `python-pillow` be listed as a dependency? Currently falls back to raw copy if not installed (truncated PNGs will show Qt errors in that case).
- The batch model means images appear all at once (~1-2s delay) instead of progressively. Is this acceptable UX? If progressive loading is desired, a QML `ListModel` with `append()` would be needed (incremental, no full rebuild).
- Should we increase `_maxConcurrentDecodes` from 3 to speed up the batch? With truncation detection (no PIL processing needed for truncated images), the queue processes faster.
