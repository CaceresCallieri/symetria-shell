# Deferred Panels Loading — Implementation Plan

**Date:** 2026-04-04
**Branch:** `fix/deferred-panels-v2`
**Based on:** Previous implementation in `git stash@{2}` (13 files changed, 470 insertions, 378 deletions)

---

## Why This Change Exists

### The Startup Problem

Symmetria's startup freezes the event loop because of how Quickshell's reload walk interacts with a large synchronous component tree. The entire investigation is at `docs/startup-delay-investigation/`.

**The key numbers:**

| Configuration | Freeze (Qt 6.10.2) | Freeze (Qt 6.11.0) |
|---|---|---|
| Full shell (current) | **22s** | **91s** |
| Shell without Drawers | 671ms | 671ms |
| Drawers with stubbed Panels | 672ms | 672ms |
| **Target (deferred loading)** | **~1s** | **~1-3s** |

The freeze is caused by `Panels.qml` importing 12 module directories (~160 QML files, ~1,400 property bindings) that are all evaluated during Quickshell's `EngineGeneration::onReload()` synchronous reload walk. If Panels' heavy sub-trees don't exist during the reload walk, the freeze drops to <1 second.

### Root Cause: Qt 6.11.0 Regression

Qt 6.11.0 introduced a ~4x regression in QML binding evaluation, confirmed on 2026-04-04 by downgrading Qt to 6.10.2 on the same system with the same code. The regression is in Qt's `QQmlPropertyCache` changes ("Do not store type references for properties") and/or property shadowing runtime enforcement. Qt is pinned to 6.10.2 as a workaround, but this fix benefits both Qt versions.

Full details: `docs/startup-delay-investigation/00-summary.md`

---

## Previous Implementation (stash@{2})

A previous attempt exists in `git stash@{2}`. It modified 13 files and achieved **8.8s → 1.0s** on Qt 6.10.2 (with Quickshell r67). Here's what it did:

### Strategy: Two-Layer Deferral

**Layer 1: Defer the entire Drawers content tree**
- `Drawers.qml` was gutted to a minimal Variants + LazyLoader wrapper
- All content moved to `content/DrawersImpl.qml`
- DrawersImpl uses **relative path imports** (e.g., `import "../../bar"`) instead of `qs.modules.*` paths (which don't resolve in URL-loaded files — see `docs/startup-delay-investigation/05-quickshell-limitations.md`)

**Layer 2: Defer individual panels within Panels.qml**
- Heavy panel imports (Session, Launcher, Dashboard, Clipboard, Askpass, STT, Calculator, Packages) removed from Panels.qml's import section
- Each panel replaced with a `Loader` that calls `setSource()` on first visibility toggle
- Lightweight panels (Utilities, Sidebar, BarPopouts, Toasts) kept eagerly loaded
- `Backgrounds.qml` moved to `backgrounds/Backgrounds.qml` subdirectory and also loaded via `setSource()` with relative imports

**Layer 3: Defer bar popouts**
- `BarWrapper.qml`: changed `sourceComponent: Bar {}` to `setSource(Qt.resolvedUrl("Bar.qml"), {...})`
- `bar/popouts/Wrapper.qml`: removed `import qs.modules.controlcenter` (49 files) and `import qs.modules.windowinfo` (4 files), loaded via `setSource()` on demand
- `Calendar.qml` moved to `calendarcontent/Calendar.qml` subdirectory

### Files Modified in Previous Attempt

| File | Change |
|---|---|
| `modules/drawers/Drawers.qml` | Gutted to Variants + LazyLoader wrapper (17 lines) |
| `modules/drawers/content/DrawersImpl.qml` | **New** — full Drawers content with relative imports |
| `modules/drawers/Panels.qml` | Heavy imports removed, replaced with Loader + setSource |
| `modules/drawers/Backgrounds.qml` → `backgrounds/Backgrounds.qml` | Moved to subdirectory, relative imports |
| `modules/bar/BarWrapper.qml` | sourceComponent → setSource for Bar.qml |
| `modules/bar/popouts/Wrapper.qml` | Removed controlcenter/windowinfo imports, use setSource |
| `modules/bar/popouts/Content.qml` | Calendar → calendarcontent/Calendar.qml |
| `modules/bar/popouts/Calendar.qml` → `calendarcontent/Calendar.qml` | Moved to subdirectory |
| `modules/session/Background.qml` | `required property Wrapper wrapper` → `Item wrapper` |
| `modules/sidebar/Background.qml` | Same type relaxation |
| `modules/utilities/Background.qml` | Same type relaxation |
| `modules/utilities/cards/Toggles.qml` | Removed unused controlcenter import |
| `shell.qml` | Added heartbeat profiler |

### What Worked

1. **Drawers → LazyLoader → DrawersImpl**: Successfully deferred the entire Drawers content tree. The reload walk saw an empty LazyLoader and completed instantly.
2. **Panels → Loader + setSource**: Individual panels loaded on first visibility toggle. Relative paths resolved correctly.
3. **Background type relaxation**: `Wrapper` → `Item` worked (only .width/.height accessed).
4. **Unused import removal**: Toggles.qml controlcenter import removed.
5. **Startup time**: 8.8s → 1.0s on Qt 6.10.2 (r67).

### What Had Issues / Unknowns

1. **Panels not appearing after load** — The user reports that panels were deferred but didn't visually appear once loaded. This needs investigation — likely a binding or visibility issue where the Loader's item doesn't propagate correctly to the parent layout.

2. **ControlCenter close() function** — The original had `function close(): void { root.close(); }` defined inline in the sourceComponent. With `setSource()`, this function can't be passed as a property. Needs an alternative (signal, or the loaded component calls a method on root).

3. **Current codebase differences** — The stash was made against the `fix/deferred-panel-loading` branch, which is older than current `main`. Key differences:
   - Current `main` does NOT have `import qs.modules.keychords as KeyChordsModule` in Drawers.qml (keychords moved to its own WlrLayer.Overlay in shell.qml)
   - Current `main` has `import qs.modules.stt as SttModule` in Bar.qml (STT bar embed feature)
   - Current `main` has `KillConfirm` and `KillConfirmOverlay` in shell.qml
   - Current `main` does NOT have `visibilities.keychords` in Drawers (keychords decoupled)
   - Background type relaxation (Wrapper → Item) already applied on main
   - Unused controlcenter import already removed on main

4. **Interactions.qml nullable guards** — The stash made `panels` and `popouts` nullable in Interactions, adding null guards to hover/click handlers. These are fragile — any new handler that forgets the guard will crash.

5. **LazyLoader vs Loader** — The stash used Quickshell's `LazyLoader` for Drawers.qml, but the investigation says "Variants does not support async loading inside LazyLoader." However, the stash used `LazyLoader` WITH `loading: true` and a URL source — the docs might mean that LazyLoader's `loading` control doesn't work as expected inside Variants, but `source` + `loading: true` on initial load might be fine.

---

## Implementation Plan for v2

### Pre-Implementation: Research Phase

Before coding, research the following:

1. **Quickshell's LazyLoader behavior** — Read the Quickshell source/docs to understand exactly how LazyLoader works inside Variants. What does `loading: true` actually do? Does it defer to after the reload walk? Search Quickshell's source for `LazyLoader`, `IncubationController`, and `AsyncLoader`.

2. **QML Loader asynchronous behavior** — Research Qt's documentation on `Loader { asynchronous: true }` and `setSource()`:
   - When exactly does the loaded component become `item`?
   - Does `asynchronous: true` affect when bindings are evaluated?
   - How does Qt's `QQmlIncubator` work with `setSource()` vs `source` vs `sourceComponent`?
   - What is the correct pattern for passing `Qt.binding()` functions via `setSource()`?

3. **Why panels didn't appear** — The critical bug from the previous attempt. Research:
   - Does `Loader.item` propagate `visible`, `width`, `height` correctly to parent?
   - Do `anchors` on a Loader work correctly when the item is loaded asynchronously?
   - Is there a `Loader.onLoaded` signal we should use to trigger visibility?
   - Check if the issue was that `visible: item?.visible ?? false` on the Loader prevents the item from ever becoming visible (circular: Loader invisible → item not visible → Loader stays invisible).

4. **Relative imports in setSource-loaded files** — Verify that `../../session/Wrapper.qml` loaded via `setSource()` can import:
   - `qs.components` ✓ (confirmed in investigation)
   - `qs.services` ✓ (confirmed)
   - `qs.config` ✓ (confirmed)
   - `import ".."` for sibling types ✓ (confirmed for drawers)
   - `import "../../bar"` for cross-module refs ✓ (confirmed)
   - **But NOT `qs.modules.*`** ✗ (confirmed limitation)

### Phase 1: Adapt Previous Implementation to Current Codebase

**Goal:** Get the stash@{2} approach working on current `main`.

1. **Don't split Drawers into DrawersImpl** — The previous approach moved ALL Drawers content to `content/DrawersImpl.qml`. This is unnecessary if we only defer Panels' heavy imports. Instead, keep Drawers.qml's structure but wrap the Panels instantiation in a Timer + Loader.

2. **Simpler approach — defer only Panels' heavy sub-trees:**

   ```qml
   // In Drawers.qml — keep everything as-is, but Panels loads after reload walk
   Panels {
       id: panels
       // ... all current properties ...
   }
   ```
   
   Change to:
   
   ```qml
   // Panels is now loaded after the reload walk via Timer { interval: 0 }
   Loader {
       id: panelsLoader
       active: false
       
       // Activate on first event loop tick after reload completes
       Timer {
           id: deferTimer
           interval: 0
           running: true
           onTriggered: panelsLoader.active = true
       }
       
       sourceComponent: Panels {
           id: panels
           screen: scope.modelData
           visibilities: visibilities
           bar: bar
           agentBar: agentBar
       }
   }
   
   // Alias for all references to "panels"
   property alias panels: panelsLoader.item
   ```

   **Wait — this won't work.** The investigation says Variants forces synchronous compilation, so even `Loader` inside Variants is sync. But the stash@{2} used Timer { interval: 0 } and it DID work. The difference is: `sourceComponent` compiles at parent compile time (eager), while `setSource()` compiles at call time (deferred). So we need `setSource()`, not `sourceComponent`.

3. **Correct approach — Timer + setSource:**

   ```qml
   Loader {
       id: panelsLoader
       
       Timer {
           interval: 0
           running: true
           onTriggered: panelsLoader.setSource(
               Qt.resolvedUrl("Panels.qml"),
               { screen: scope.modelData, visibilities: visibilities, bar: bar, agentBar: agentBar }
           )
       }
   }
   ```
   
   **But this won't work either** — Panels.qml is in the same directory as Drawers.qml, so it's already registered as a type. When Drawers compiles, ALL files in the `drawers/` directory are scanned and registered. Panels.qml would be compiled as part of the directory scan.
   
   **Solution:** Move Panels.qml to a subdirectory (e.g., `drawers/panels/Panels.qml`) so it's NOT compiled during the `drawers/` directory scan. Then load via `setSource(Qt.resolvedUrl("panels/Panels.qml"), {...})`.

4. **Alternatively — strip heavy imports from Panels.qml directly:**

   Keep Panels.qml in the `drawers/` directory, but remove all heavy `qs.modules.*` imports and replace each panel component with a Loader + `setSource()` using relative paths. This is what stash@{2} did, and it keeps the file in place (no moves needed).

### Phase 2: Fix the "Panels Not Appearing" Bug

This is the critical issue from the previous attempt. Likely causes:

1. **Circular visibility binding** — `visible: item?.visible ?? false` on the Loader means the Loader is invisible until its item is visible, but the item might check ITS parent's visibility (the Loader) and also be invisible. Fix: don't gate Loader visibility on item visibility.

2. **Anchoring issues** — `anchors.horizontalCenter: parent.horizontalCenter` on the Loader might not work until the Loader has an item with width. Fix: set explicit width/height on the Loader from the loaded item.

3. **Missing signal connection** — The `visibilities.onLauncherChanged` handler calls `setSource()`, which loads the component asynchronously. But the visibility toggle might have already fired and been consumed before the component finishes loading. Fix: after `setSource()`, re-apply the visibility state.

4. **Implicit size not propagated** — Loader needs `implicitWidth`/`implicitHeight` from its item to participate in parent layouts. Fix: bind Loader dimensions to item dimensions.

### Phase 3: Handle Bar Popout Deferral

Defer the heaviest cascade: `qs.modules.controlcenter` (49 files) and `qs.modules.windowinfo` (4 files) from `bar/popouts/Wrapper.qml`.

1. Remove the imports from Wrapper.qml
2. In the `DetachedComp` for each, use `setSource()` with relative paths:
   - `Qt.resolvedUrl("../../controlcenter/ControlCenter.qml")`
   - `Qt.resolvedUrl("../../windowinfo/WindowInfo.qml")`
3. Handle the `close()` function for ControlCenter (can't be passed as a property via setSource — use a signal or Connections pattern)

### Phase 4: Verify & Measure

1. Clear QML cache and restart
2. Measure heartbeat timing
3. Verify all panels appear correctly when toggled
4. Test on both Qt 6.10.2 and Qt 6.11.0
5. Check for regression in panel animations, focus grab, hover interactions

---

## Key Quickshell/QML Concepts for This Work

### qs.modules.* Path Resolution (CRITICAL LIMITATION)

Files loaded via `Loader.setSource(url)` or `Loader.source = url` CANNOT use `qs.modules.*` import paths. Only these work:

| Import Path | Works in setSource? |
|---|---|
| `qs.components` | ✓ |
| `qs.services` | ✓ |
| `qs.config` | ✓ |
| `qs.utils` | ✓ |
| `Quickshell`, `QtQuick`, etc. | ✓ |
| Relative paths (`../../bar`) | ✓ |
| **`qs.modules.*`** | **✗** |

**Implication:** Any file loaded via setSource that currently imports `qs.modules.foo` must be changed to `import "../../foo"` (relative path).

### Variants + Synchronous Compilation

Quickshell's `Variants` component forces synchronous compilation of its children. `Loader { asynchronous: true }` inside Variants completes synchronously. The ONLY way to truly defer is:

1. Use `Timer { interval: 0 }` to delay the `setSource()` call until AFTER the reload walk
2. Or use `LazyLoader` with `loading: true` (Quickshell-specific, may work differently)

### sourceComponent vs source vs setSource

| Pattern | When compiled? | Properties? |
|---|---|---|
| `sourceComponent: Foo {}` | When PARENT compiles (eager) | Inline |
| `source: "Foo.qml"` | When Loader activates | Can't pass initial properties |
| `setSource("Foo.qml", {props})` | When called (deferred) | Via property map |

For deferred loading, `setSource()` is the correct choice because it defers BOTH compilation AND allows passing initial properties.

### Qt.binding() in setSource

Properties passed to `setSource()` are normally one-time assignments. To create live bindings, wrap in `Qt.binding()`:

```qml
setSource(Qt.resolvedUrl("Foo.qml"), {
    screen: scope.modelData,                          // one-time assignment (ShellScreen doesn't change)
    height: Qt.binding(() => root.contentHeight),     // live binding
    client: Qt.binding(() => Hypr.activeToplevel)     // live binding
});
```

---

## Current File State Reference

### modules/drawers/Drawers.qml (238 lines)
- Imports: `qs.components`, `qs.components.containers`, `qs.services`, `qs.config`, `qs.modules.bar`, `qs.modules.agentbar`
- Structure: Variants → Scope → StyledWindow containing Bar, AgentBar, Panels, Interactions, Backgrounds, Border, Visibilities, FocusGrab
- No keychords import (moved to own overlay in shell.qml)

### modules/drawers/Panels.qml (226 lines)
- Imports 12 modules: Session, Launcher, Dashboard, BarPopouts, Utilities, Toasts, Sidebar, Clipboard, Askpass, STT, Calculator, Packages
- Creates all panel Wrapper instances eagerly
- Required properties: screen, visibilities, bar, agentBar

### modules/bar/BarWrapper.qml (~90 lines)
- Uses `Loader` with `sourceComponent: Bar {}` — Bar is compiled eagerly
- Required properties: screen, visibilities, popouts, disabled

### modules/bar/popouts/Wrapper.qml
- Imports `qs.modules.controlcenter` (49 files!) and `qs.modules.windowinfo` (4 files)
- Uses `sourceComponent: ControlCenter {}` and `sourceComponent: WindowInfo {}` — eager

### Key Changes Since Previous Attempt (stash@{2})
- ✅ Background type relaxation (Wrapper → Item) — already applied
- ✅ Unused controlcenter import from Toggles.qml — already removed
- ❌ Keychords no longer in Drawers (moved to shell.qml WlrLayer.Overlay)
- ❌ STT bar embed added to Bar.qml (new import: qs.modules.stt)
- ❌ KillConfirm/KillConfirmOverlay added to shell.qml
- ❌ Several new properties and bindings in Drawers/Interactions

---

## Success Criteria

1. **Shell startup < 3 seconds** on Qt 6.10.2 (current: 22s)
2. **All panels appear correctly** when toggled (the bug from v1)
3. **No regression** in panel animations, focus grab, hover interactions
4. **Heartbeat profiler** confirms event loop is responsive within 1-2 seconds
5. **Both Qt 6.10.2 and 6.11.0** show improvement (6.11.0 should drop from 91s to ~5-15s)
