# Root Cause Analysis

## The Two Independent Blockers

The ~18-20 second startup delay has **two independent root causes** that overlap:

### 1. QML Directory Import Compilation (~18-20s)

When `shell.qml` does `import "modules/drawers"`, the QML engine registers all types in the drawers directory. When `Drawers {}` is instantiated, `Drawers.qml` is compiled. Its `import qs.modules.bar` (and other imports) cascade to compile dozens of additional files.

**The import cascade from Drawers.qml:**
```
Drawers.qml
  ├─ import qs.modules.bar → Bar.qml, BarWrapper.qml
  │    ├─ BarWrapper.qml: import "popouts" → 15 files in bar/popouts/
  │    │    ├─ Wrapper.qml: import qs.modules.controlcenter → 49 files!
  │    │    ├─ Wrapper.qml: import qs.modules.windowinfo → 4 files
  │    │    └─ Calendar.qml: import qs.modules.dashboard.dash → 14 files
  │    └─ Bar.qml: import "components" + "components/workspaces" → ~25 files
  ├─ import qs.modules.agentbar → 9 files
  ├─ import qs.modules.keychords → 3 files
  └─ (directory scan) → Panels.qml, Interactions.qml, Backgrounds.qml, etc.
       ├─ Panels.qml: import qs.modules.session → 3 files
       ├─ Panels.qml: import qs.modules.launcher → 16 files
       ├─ Panels.qml: import qs.modules.dashboard → 14 files
       ├─ Panels.qml: import qs.modules.clipboard → 8 files
       ├─ Panels.qml: import qs.modules.calculator → 4 files
       ├─ Panels.qml: import qs.modules.askpass → 5 files
       ├─ Panels.qml: import qs.modules.stt → 5 files
       ├─ Panels.qml: import qs.modules.packages → 7 files
       ├─ Panels.qml: import qs.modules.utilities → 11 files
       ├─ Panels.qml: import qs.modules.sidebar → 10 files
       ├─ Backgrounds.qml: (same 11 modules as Panels — cache hits)
       └─ Interactions.qml: import qs.modules.bar.popouts → (cache hit)
```

**Additional cascade from shell.qml:**
```
modules/Shortcuts.qml: import qs.modules.controlcenter → 49 files!
modules/utilities/cards/Toggles.qml: import qs.modules.controlcenter → (cache hit, but unused!)
```

### 2. Quickshell.Services.Notifications C++ Module (~19s)

`Notification.qml` imports `Quickshell.Services.Notifications` — a C++ framework module that performs **blocking D-Bus notification daemon registration**. This blocks the main thread for ~19 seconds regardless of whether the QML file is loaded synchronously or asynchronously.

**Proof:** Adding just `import Quickshell.Services.Notifications` to a bare window file (with no component creation) causes the full 19-second freeze. Similarly, `import Quickshell.Widgets` also triggers the delay (likely a dependency chain).

## Why The Delay Is Constant (~18-20s)

Both blockers produce approximately the same delay (~18-20s). When present together, they overlap (same initialization phase). Fixing one without the other shows no improvement because the remaining blocker still fills the same time window.

## What Does NOT Cause The Delay

Verified through isolation testing:
- **GPU shader compilation** — Mesa shader cache (67MB) exists and is used
- **EGL/OpenGL context creation** — benchmarked at 1ms per context, 9 contexts = 9ms
- **Font loading** — Material Symbols Rounded (14MB) contributes some time but is secondary
- **Network requests** — All async, complete within 1-5s but callbacks blocked by the freeze
- **Subprocess launches** — All async (nmcli, ddcutil, ipinfo.io, cliphist)
- **Background module** — Tested disabled, no change in delay
- **Individual service singletons** — All complete in <200ms collectively
- **QML bytecode cache** — Tested with warm cache, delay identical (~18.2s vs ~18.9s cold)
- **Number of windows** — 5 empty windows = 0ms delay; 1 complex window = 18s delay

## Critical Insight: Compilation vs Instantiation

QML types are **compiled on first instantiation**, not on import. The `import "modules/drawers"` statement only REGISTERS type names from the directory. The actual compilation of `Drawers.qml` (and its cascading imports) happens when `Drawers {}` appears in shell.qml.

**Proof:**
- Commenting out `Drawers {}` while keeping `import "modules/drawers"` → instant
- Keeping `Drawers {}` but stripping Drawers.qml to bare content → instant
- Full Drawers.qml with all imports → 18-20s delay
