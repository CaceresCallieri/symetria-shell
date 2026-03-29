# Import Cascade Map

## Total QML Files Per Module

| Module | Top-Level Files | With Subdirs | Heavy Cascades |
|--------|----------------|--------------|----------------|
| `modules/` (root) | 3 | 3 | Shortcuts.qml → controlcenter (49) |
| `modules/drawers/` | 6 | 6 | Panels/Backgrounds → 8 module dirs |
| `modules/background/` | 4 | 4 | None |
| `modules/areapicker/` | 2 | 2 | None |
| `modules/osd/` | 2 | 2 | None |
| `modules/notifications/` | 3 | 3 | Quickshell.Services.Notifications (C++) |
| `modules/lock/` | 12 | 12 | None |
| `modules/askpass/` | 4 | 6 | None (local "services" subdir) |
| `modules/stt/` | 5 | 5 | None |
| `modules/keycaster/` | 5 | 5 | None |
| `modules/keychords/` | 3 | 3 | None |
| `modules/bar/` | 2 | ~40 | popouts → controlcenter, windowinfo, dashboard |
| `modules/agentbar/` | 9 | 9 | None |
| `modules/controlcenter/` | ~12 | **49** | appearance, audio, bluetooth, launcher, network, taskbar subdirs |
| `modules/dashboard/` | ~6 | **14** | dash subdirectory |
| `modules/windowinfo/` | 4 | 4 | None |
| `modules/session/` | 3 | 3 | None |
| `modules/launcher/` | ~8 | **16** | services subdirectory |
| `modules/clipboard/` | ~5 | **8** | None |
| `modules/calculator/` | 4 | 4 | None |
| `modules/packages/` | ~5 | **7** | None |
| `modules/utilities/` | ~7 | **11** | cards subdirectory |
| `modules/sidebar/` | 10 | 10 | None |

## Heaviest Cascade Chains

### Chain 1: Drawers → bar/popouts → controlcenter (biggest)
```
Drawers.qml
  → qs.modules.bar (2 files)
    → BarWrapper.qml imports "popouts" (15 files)
      → Wrapper.qml imports qs.modules.controlcenter (49 files)
      → Wrapper.qml imports qs.modules.windowinfo (4 files)
      → Calendar.qml imports qs.modules.dashboard.dash (14 files)
Total from this chain: ~84 files
```

### Chain 2: Drawers → Panels → 8 module directories
```
Panels.qml (in drawers/ directory, compiled at directory scan)
  → qs.modules.session (3)
  → qs.modules.launcher (16)
  → qs.modules.dashboard (14)
  → qs.modules.clipboard (8)
  → qs.modules.calculator (4)
  → qs.modules.askpass (5)
  → qs.modules.stt (5)
  → qs.modules.packages (7)
  → qs.modules.bar.popouts (cache hit from Chain 1)
  → qs.modules.utilities (11)
  → qs.modules.sidebar (10)
Total from this chain: ~83 files (some cache hits)
```

### Chain 3: Shortcuts → controlcenter
```
modules/Shortcuts.qml (in root, compiled at directory scan)
  → qs.modules.controlcenter (49 files, cache hit if Chain 1 already ran)
```

### Chain 4: Backgrounds → same as Panels (all cache hits)
```
Backgrounds.qml (in drawers/ directory)
  → same 11 module directories as Panels (all cache hits)
```

## Files That Import qs.modules.controlcenter (49 files!)

The controlcenter module is the single heaviest cascade target:

| File | How it reaches controlcenter |
|------|------------------------------|
| `modules/Shortcuts.qml` | Direct import |
| `modules/bar/popouts/Wrapper.qml` | Direct import |
| `modules/bar/components/Settings.qml` | Direct import (deferred by Bar setSource) |
| `modules/bar/components/SettingsIcon.qml` | Direct import (deferred by Bar setSource) |
| `modules/utilities/cards/Toggles.qml` | **UNUSED import** — can be safely removed |
| `modules/controlcenter/*.qml` | Self-referential (internal) |

## Unused Import Found

`modules/utilities/cards/Toggles.qml` imports `qs.modules.controlcenter` but does NOT use any type from it. Confirmed by checking all controlcenter type names against the file contents. This import should be removed regardless of other fixes.
