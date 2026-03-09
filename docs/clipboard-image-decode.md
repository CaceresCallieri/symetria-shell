# Clipboard Image Decode: Truncated PNGs & Progressive Loading

## Problem

Clipboard images frequently failed to display in the image grid -- 5 of 12 cached images had truncated PNG data from the Wayland clipboard, producing Qt `libpng error: Read Error` and blank thumbnails. Additionally, the image grid flickered on every decode completion: each time a single image finished decoding, **all** delegates were destroyed and recreated, causing a visible flash even though the pixel data was cached.

Symptoms:
```
libpng error: Read Error
WARN scene: QML QQuickImage at @modules/clipboard/ImageGridItem.qml: Error decoding: file:///.../5234.png: Unable to read image data
```

Reproduction: Open clipboard drawer, switch to Images tab. Any entry stored from a clipboard source that closed before full transfer completes appears as a blank/error tile. Every valid decode causes the entire grid to flash.

## Root Cause

**Two independent root causes** combined to make the image grid unreliable:

### 1. Wayland clipboard truncation (data corruption at source)

`wl-paste --watch cliphist store` stores partial PNG data when the source application closes its Wayland data offer before the full transfer completes. The resulting entries have:
- Valid PNG headers (IHDR chunk present)
- Missing IEND terminator
- Exact-KiB file sizes (65536, 106496, 131072 bytes) -- characteristic of read-buffer-aligned truncation
- Complete PNGs, by contrast, have non-round sizes (66982, 161636, 642245 bytes)

This is a fundamental Wayland protocol limitation: the clipboard uses pipe-based data transfer, and if the source disconnects mid-transfer, the consumer gets whatever bytes were already buffered.

### 2. JS array model identity semantics (grid flicker)

QML `GridView` treats a plain JS array as an opaque model. When the array **reference** changes -- even if contents are identical plus one new item -- GridView **destroys ALL delegates** and recreates them. The original implementation used a reactive binding:

```qml
// Content.qml — old approach
readonly property var imageEntries: Clipboard.entries.filter(e => e.imagePath !== "")
```

`.filter()` always returns a new array reference. This binding re-evaluated on every `imagePath` change (12+ valid decodes) AND every `skipped` change (8+ truncated skips). Each re-evaluation triggered a full delegate rebuild. With ~20 model changes and 12 delegates, this produced approximately 240 unnecessary image loads and continuous visual flicker.

`cache: true` on the `Image` component does not fix the flicker: even though pixels load instantly from Qt's in-memory cache, the QML item lifecycle (destroy, create, layout, render) still takes at least one frame, producing a visible gap.

## Solution

The fix has three parts:

### 1. Truncated PNG detection (skip, don't salvage)

The decode script (`scripts/cliphist-decode-image.sh`) uses **strict** PIL validation -- no `LOAD_TRUNCATED_IMAGES`. Calling `img.load()` on a truncated PNG raises an exception. The script uses semantic exit codes:

| Exit Code | Meaning | QML Response |
|-----------|---------|--------------|
| 0 | Success -- valid, resized PNG written | Set `imagePath`, increment valid count |
| 1 | Error -- decode/write failure | Log warning, attempt backfill |
| 2 | Truncated -- valid header but incomplete data | Skip silently, attempt backfill |

Initially, truncated PNGs were salvaged with `LOAD_TRUNCATED_IMAGES = True`, which fills missing data with black. This produced images with large black regions that users perceived as broken duplicates. Skipping them entirely is the better UX.

### 2. Progressive ListModel (no flicker)

Replaced the reactive JS array binding with a QML `ListModel` populated via `append()`. GridView treats `ListModel` mutations as incremental operations -- `append()` creates one new delegate without destroying existing ones.

```qml
// Clipboard.qml — new approach
property ListModel decodedImageEntries: ListModel {}

// On successful decode:
decodedImageEntries.append({ entry: clipboardEntry })

// Content.qml
model: Clipboard.decodedImageEntries
```

### 3. Self-replenishing decode pool

When truncated images are skipped, `_backfillFromPool()` pulls the next undecoded image from `_imagePool` (entries beyond the initial `maxImagesDisplayed` batch). This ensures the grid fills to the configured maximum (12) even with high truncation rates. In testing: 8 truncated entries were skipped, and 12 valid images were decoded from a pool of 20.

## Key Findings

**JS array model identity**: In QML, `.filter()`, `.map()`, `.slice()`, and any array method that returns a new array will cause `GridView`/`ListView` to destroy and recreate ALL delegates. Use `ListModel` with `append()`/`remove()` for progressive, flicker-free updates.

**Truncated PNG fingerprint**: Files with exact-KiB sizes (multiples of 1024 bytes) and missing IEND terminators are almost certainly Wayland clipboard truncation artifacts. Verify with `tail -c 8 <file> | od` -- complete PNGs end with bytes `49454e44ae426082`.

**PIL strict load as a validator**: `PIL.Image.open(path)` succeeds on truncated PNGs (it only reads the header). `img.load()` without `LOAD_TRUNCATED_IMAGES` forces full decompression and raises on incomplete IDAT streams. This is the most reliable truncation detector available in Python.

**Qt Image `cache: true` is safe once only valid images reach the grid**: The original `cache: false` workaround was added because Qt cached failed decode results. With truncated images now filtered out at the script level, `cache: true` is correct and avoids redundant disk reads.

**ffmpeg and ImageMagick cannot salvage truncated PNGs**: Both fail on the incomplete IDAT/zlib streams. Only PIL's forgiving `LOAD_TRUNCATED_IMAGES` mode can produce output, but the result (black-filled regions) is not useful for thumbnails.

**Batch vs progressive loading tradeoff**: A single batch assignment (`decodedImageEntries = filteredArray`) eliminates flicker but introduces a 1-2 second delay before any images appear. `ListModel.append()` provides progressive loading (images appear as they decode) with zero flicker -- the better approach for perceived performance.

## Affected Components

| File | Role | Changes |
|------|------|---------|
| `services/Clipboard.qml` | Core service: decode queue, ListModel, backfill pool | Added `decodedImageEntries` ListModel, `_imagePool`, `_backfillFromPool()`, semantic exit code handling, `skipped` property on entries |
| `scripts/cliphist-decode-image.sh` | Decode pipeline: cliphist -> PIL validate/resize -> atomic write | Strict PIL load (no `LOAD_TRUNCATED_IMAGES`), exit code 2 for truncated |
| `modules/clipboard/Content.qml` | Image grid model binding | Changed from reactive `.filter()` to `Clipboard.decodedImageEntries` ListModel |
| `modules/clipboard/ImageGrid.qml` | GridView with delegate pattern | Model source changed to ListModel |
| `modules/clipboard/ImageGridItem.qml` | Image thumbnail display | `cache: true` restored, diagnostic handlers removed |
| `modules/clipboard/ClipboardItem.qml` | Text list image thumbnails | `cache: true` restored |
| `config/ClipboardConfig.qml` | Configuration | `maxImagesDisplayed: 12` controls decode batch size |

## Prevention

**Use `ListModel` for any dynamically-populated GridView/ListView model.** Plain JS arrays are appropriate only for static, unchanging data. If the model will be built incrementally (async decode, network fetch, search results), always use `ListModel` with `append()`/`remove()` to avoid the full-delegate-rebuild trap.

**Validate external data at the boundary.** Wayland clipboard data is untrusted input -- it may be truncated, corrupted, or in an unexpected format. Validate before caching, not after loading into Qt. The decode script is the validation boundary: only files that pass strict PIL `img.load()` are written to the cache directory.

**Use semantic exit codes in shell scripts called from QML.** Differentiating between "error" (exit 1) and "known-bad input" (exit 2) allows QML to handle each case appropriately -- retry vs skip vs backfill. This pattern is reusable for any external validation pipeline.

**Check file sizes for truncation heuristics.** Exact power-of-two or KiB-aligned sizes in binary formats (PNG, JPEG) are a strong signal of buffer-aligned truncation. This can be used as a fast pre-filter before expensive validation.

**Never re-decode or re-validate at render time.** Once an image passes validation and is written to cache, trust it. `cache: true` on `Image` components avoids redundant disk reads. The validation boundary (decode script) is the single source of truth for image validity.
