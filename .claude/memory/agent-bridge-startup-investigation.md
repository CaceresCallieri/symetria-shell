# Agent Bridge & Startup Investigation

## Status: COMPLETE — All fixes implemented and verified

Last updated: 2026-03-06 (session 4)

---

## All Fixes (working, verified, ready to commit)

### 1. Python-side Emit Coalescing (`scripts/agent-bridge.py`)
- Leading edge: first event emits immediately, starts 50ms cooldown
- Trailing edge: if dirty when cooldown ends, emit once more
- Replaced all 9 `self._emit()` call sites with `self._schedule_emit()`
- **Result:** 30+ stdout emissions per startup burst → 2-3

### 2. QML-side Throttling (`services/AgentService.qml`)
- Added `_pendingUpdate`/`_throttleActive` + `bridgeThrottle` Timer (100ms)
- Leading-edge fires immediately, subsequent buffered; notifications bypass
- Extracted `_applyBridgeUpdate(parsed)` function
- **Result:** QML binding cascades reduced to 1-2 per burst

### 3. SIGKILL Crash Loop Fix (`scripts/agent-bridge.py`)
- Renamed to `_signal_stale_bridges()`, SIGTERM only, no sleep, no SIGKILL
- Relies on socket path takeover for exclusion

### 4. Backoff Reset Timer Fix (`services/AgentService.qml`)
- Changed `backoffResetTimer.restart()` → `if (!running) .start()`
- Timer fires once after 10s of stability

### 5. QT_QPA_PLATFORM pragma (`shell.qml`)
- Added `//@ pragma Env QT_QPA_PLATFORM=wayland` to force native Wayland
- Eliminates layer-shell warnings from user's `QT_QPA_PLATFORM=xcb` in `~/.zshenv`

### 6. Deferred Panels Loading (`modules/drawers/Drawers.qml` + 3 files)
- Wrapped `Panels` in `Loader { active: false }` activated by `Timer { interval: 0 }`
- Wrapped `Backgrounds` in a Loader activated when `win._panels !== null`
- Guarded `hasFullscreen`, `dragMaskPadding`, `focusGrab.active` with `_ready` flag
- Changed `Interactions.panels/popouts` and `BarWrapper.popouts` from `required` to optional
- Added null guards in Interactions handlers and Bar functions
- **Result:** Startup from ~8.8s → ~1.0s (7-9x speedup)

### Files modified (git diff):
- `scripts/agent-bridge.py` — fixes 1, 3
- `services/AgentService.qml` — fixes 2, 4
- `shell.qml` — fix 5
- `modules/drawers/Drawers.qml` — fix 6 (deferred loading, binding guards)
- `modules/drawers/Interactions.qml` — fix 6 (nullable panels/popouts, handler guards)
- `modules/bar/BarWrapper.qml` — fix 6 (nullable popouts)
- `modules/bar/Bar.qml` — fix 6 (nullable popouts, function guards)

---

## Root Cause Analysis (for reference)

The 7-10s startup delay was 100% CPU-bound QML binding evaluation during Quickshell's C++ "reload" phase. The `EngineGeneration::onReload()` method recursively walks every QObject child in the tree, calling `reload()` on Reloadable nodes. Each reload triggers property changes that cascade through the binding graph super-linearly — Bar alone took 526ms, but full Drawers took 8874ms (17x increase). 80% of CPU was in `libQt6Qml.so`, with 21% in V4 array allocation from JS operations like `.values.some()`.

**Solution:** Defer the Panels sub-tree (14 panel Wrappers + Backgrounds) to a post-reload Loader. During the reload walk, the Loader has no children — the entire cascade-producing sub-tree is absent. Panels are created on the first event loop tick after reload completes, in normal event processing without the compounding reload cascade.

### Timing Results

| Config | Before | After |
|--------|--------|-------|
| Bar alone | 526ms | 526ms |
| Full shell | 7,019-8,874ms | **~1,000ms** |
| Minimal (no modules) | 504ms | 504ms |

---

## Test Infrastructure

- **Minimal test config:** `~/.config/quickshell/startup-test/shell.qml` (504ms baseline)
- **GNU time:** installed (`/usr/bin/time -v`)
- **perf:** installed, data at `/tmp/qs-perf.data`
- **Quickshell debug sources:** `/usr/src/debug/quickshell-git/quickshell/src/`
