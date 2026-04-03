# AGS Bar Reference (Features to Port)

The previous system bar is at `~/.config/ags/` — an AGS (Astal GTK Shell) implementation using TypeScript/TSX with GTK3. Several features from this bar should be ported to Symmetria's QML/Qt6 architecture.

## AGS Directory Structure
```
~/.config/ags/
├── bar/
│   ├── Bar.tsx              # Main bar component
│   ├── modules/             # Bar modules
│   │   ├── Kanata.tsx       # Keyboard remapper status
│   │   ├── StatusPanel.tsx  # Volume, battery, power
│   │   ├── SystemInfo.tsx   # RAM, CPU, GPU, updates
│   │   └── workspaces/
│   │       └── AppIcons.tsx # Per-workspace app icons
│   ├── widget/              # Individual widgets
│   │   ├── AvailableUpdates.tsx
│   │   ├── CPUStatus.tsx
│   │   ├── GPUStatus.tsx
│   │   ├── RamUsage.tsx
│   │   ├── SubmapStatusIndicator.tsx
│   │   └── Weather/
│   └── scripts/
│       └── check-available-updates.sh
└── lib/
    └── icon-resolver/       # Smart icon resolution library
```

## Features to Port

| Feature | AGS Location | Priority | Notes |
|---------|--------------|----------|-------|
| **Workspace App Icons** | `bar/modules/workspaces/AppIcons.tsx` | High | Shows running app icons per workspace; handles grouped windows, swallowed clients, click-to-focus |
| **Available Updates** | `bar/widget/AvailableUpdates.tsx` | Medium | Polls pacman/AUR/flatpak updates via `check-available-updates.sh`; shows count with tooltip breakdown |
| **Kanata Status** | `bar/modules/Kanata.tsx` | Medium | Shows keyboard remapper status; listens to Hyprland custom events `kanata-configuration-switched` |
| **Submap Indicator** | `bar/widget/SubmapStatusIndicator.tsx` | Medium | Shows current Hyprland submap (keybind modes like "groups", "groups-move-in") |
| **System Info** | `bar/modules/SystemInfo.tsx` | Low | RAM/CPU/GPU monitoring widgets (Symmetria already has similar in dashboard) |
| **Icon Resolver** | `lib/icon-resolver/` | Medium | Resolves window class → app icon; special handling for terminal apps showing nested process icons |

## Technology Translation Guide

| AGS (TypeScript/GTK3) | Symmetria (QML/Qt6) |
|-----------------------|---------------------|
| `Variable(value)` | `property var` or `QtObject` with properties |
| `bind(variable)` | QML property bindings |
| `Variable.poll(interval, cmd)` | `Timer` + `Process` from Quickshell.Io |
| `widget.hook(hyprland, "event", ...)` | `Connections` to Hyprland service |
| `exec(cmd)` / `subprocess(cmd)` | `Process { command: [...] }` |
| GTK `<box>`, `<label>`, `<button>` | QML `Row/Column`, `Text`, `MouseArea` |
| SCSS styling | QML inline properties or Symmetria's `Colours` service |

## Key Implementation Notes

**Workspace App Icons:** Uses `hyprctl clients -j` to get window list, filters by workspace, handles swallowed windows (terminal window swallowing), and sorts by screen position. The icon resolver checks `.desktop` files and has special terminal app detection.

**Available Updates Script:** Located at `~/.config/ags/bar/scripts/check-available-updates.sh` — outputs JSON with pacman, AUR, flatpak counts. Can be reused directly.

**Hyprland Custom Events:** AGS listens for custom events via `hyprctl dispatch submap` and `hyprctl dispatch custom`. Symmetria's `services/Hypr.qml` should already support this pattern.
