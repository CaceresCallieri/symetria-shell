# Attempted Fixes and Results

## Fix 1: Panels.qml Lazy Loading (PARTIALLY WORKS — blocked by other cascades)

**Approach:** Remove 8 heavy module imports from Panels.qml, replace eager `Session.Wrapper {}`, `Launcher.Wrapper {}`, etc. with `Loader` + `setSource()` that activates on first visibility.

**Result:** Import errors — `qs.modules.*` paths don't resolve in URL-loaded files. Relative path imports work (`import "../../session"`) but the delay persists because other files in the drawers/ directory (Backgrounds.qml, Drawers.qml itself) still cascade to heavy modules.

**Code written:** Full implementation exists (Panels.qml with Loader pattern + Connections for activation). See the git stash or branch history.

**Would work IF:** Combined with fixes for ALL other cascade sources AND if `qs.modules.*` paths resolved in setSource-loaded files.

---

## Fix 2: Backgrounds.qml Moved to Subdirectory (WORKS but insufficient alone)

**Approach:** Move `modules/drawers/Backgrounds.qml` to `modules/drawers/backgrounds/Backgrounds.qml` so the directory scan of `modules/drawers/` doesn't compile it. Load via `Loader { setSource("backgrounds/Backgrounds.qml", ...) }` from Drawers.qml.

**Result:** Works with relative path imports (`import "../../session"` instead of `qs.modules.session`). Also needed `required property Panels panels` changed to `required property Item panels`. But insufficient alone — the delay persists because Drawers.qml's own imports still cascade.

---

## Fix 3: BarWrapper Deferred Bar Compilation (WORKS)

**Approach:** In `modules/bar/BarWrapper.qml`, change `sourceComponent: Bar {}` to `onActiveChanged: setSource(Qt.resolvedUrl("Bar.qml"), {...})`. Defers compilation of Bar.qml and its `"components"` + `"components/workspaces"` subdirectory imports (~25 files).

**Result:** The change is valid QML — Bar.qml is in the same directory as BarWrapper.qml, so `Qt.resolvedUrl("Bar.qml")` works. But BarWrapper still imports `"popouts"` eagerly, and Bar.qml uses `qs.` module paths that resolve fine (same directory context). This fix reduces the cascade by ~25 files.

---

## Fix 4: Popouts Cascade Fix (PARTIALLY WORKS)

**Approach:**
- Remove `import qs.modules.controlcenter` and `import qs.modules.windowinfo` from `bar/popouts/Wrapper.qml`
- Change `sourceComponent: ControlCenter/WindowInfo {}` to `onShouldBeActiveChanged: setSource(url, props)`
- Move `Calendar.qml` to `calendarcontent/Calendar.qml` subdirectory

**Result:** The controlcenter/windowinfo imports are removed from the eager path. But the `setSource` URLs use relative paths (`../../controlcenter/ControlCenter.qml`, `../../windowinfo/WindowInfo.qml`) — these might fail if the loaded files import `qs.modules.*` paths internally. **NOT FULLY VERIFIED** due to other blockers masking the test.

**ControlCenter close() function:** The original had `function close(): void { root.close(); }` defined inline in the sourceComponent. With setSource, this function can't be passed as a property. Needs alternative approach (e.g., signal/slot or wrapper).

---

## Fix 5: Shortcuts.qml Moved to Subdirectory (WORKS for isolation, FAILS for module paths)

**Approach:** Move `modules/Shortcuts.qml` to `modules/shortcuts/Shortcuts.qml`, load via `Loader { source: ...; asynchronous: true }` from shell.qml.

**Result:** When loaded via URL, `qs.modules.controlcenter` doesn't resolve. Error: `module "qs.modules.controlcenter" is not installed`. Relative imports (`import "../controlcenter"`) would work but weren't tested.

---

## Fix 6: DrawersImpl.qml Split (WORKS with relative imports, BLOCKED by Variants)

**Approach:** Split Drawers.qml into:
- `Drawers.qml` — lightweight wrapper (Variants + Loader per screen, NO heavy imports)
- `content/DrawersImpl.qml` — full content with heavy imports using relative paths

**Result:** Relative imports resolve correctly. `import ".."` for sibling drawers types works. `import "../../bar"` for the bar module works. **But: Variants forces synchronous compilation** — neither `Loader { asynchronous: true }` nor `LazyLoader { loading: true }` can make the compilation incremental inside a Variants instance. The full 19s freeze persists.

**Quickshell docs confirm:** "Variants does not support async loading inside LazyLoader."

---

## Fix 7: NotificationsOverlay Deferred (PARTIALLY WORKS — freeze shifts to async phase)

**Approach:** Remove `import "modules/notifications"` from shell.qml, load via `Loader { source: ...; asynchronous: true }` with 100ms Timer delay.

**Result:**
- `Quickshell.Services.Notifications` (C++ module) still blocks ~19s during D-Bus init
- Error: `Content is not a type` — sibling types don't resolve in URL-loaded files
- Even with async Loader, the C++ module init is atomic and blocks the main thread

---

## Fix 8: Background Type Constraints (WORKS — safe standalone change)

**Approach:** Change `required property Wrapper wrapper` to `required property Item wrapper` in session/Background.qml, sidebar/Background.qml, utilities/Background.qml.

**Result:** Works. Only accesses `.width` and `.height` which are standard Item properties. No functional change — purely a type annotation relaxation.

---

## Fix 9: Remove Unused controlcenter Import (WORKS — safe standalone change)

**Approach:** Remove `import qs.modules.controlcenter` from `modules/utilities/cards/Toggles.qml`.

**Result:** Confirmed unused — no controlcenter types referenced in the file. Safe to remove.

---

## Summary: What Actually Works

| Fix | Status | Safe to Ship? |
|-----|--------|---------------|
| Background type constraints (Wrapper→Item) | Works | Yes |
| Remove unused controlcenter import (Toggles) | Works | Yes |
| BarWrapper deferred Bar compilation | Works | Probably (needs testing) |
| Popouts cascade removal | Partially works | Needs verification |
| DrawersImpl split + relative imports | Works technically | Blocked by Variants sync |
| Panels lazy loading | Works technically | Blocked by qs.modules path issue |
| Notifications deferred | Blocked | C++ module blocks atomically |
| Shortcuts moved | Blocked | qs.modules path issue |
