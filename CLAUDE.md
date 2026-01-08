# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Caelestia Shell is a Quickshell-based desktop shell for Hyprland. It provides a complete desktop UI including bar, launcher, dashboard, notifications, lock screen, and control center. This is a fork of caelestia-dots/shell for personal customization.

**Upstream:** https://github.com/caelestia-dots/shell

## Branch Structure

| Branch | Purpose | Tracks |
|--------|---------|--------|
| `main` | Active development with customizations | `origin/main` |
| `base` | Original upstream shell code (reference) | `upstream/main` |
| `feature/*` | Feature branches for significant changes | - |

### Comparing Against Upstream

```bash
# See all customizations vs original shell
git diff base..main

# List commits that diverge from upstream
git log base..main --oneline

# Update base to latest upstream
git fetch upstream
# (base automatically updates since it tracks upstream/main)
```

### Working with Feature Branches

For significant changes, create a feature branch from `main`:
```bash
git checkout -b feature/my-feature main
# ... make changes ...
git checkout main
git merge feature/my-feature
```

## Build Commands

```bash
# Configure (development mode - keeps QML in local config dir)
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/ -DINSTALL_QSCONFDIR=$HOME/.config/quickshell/caelestia

# Build
cmake --build build

# Install (requires sudo for system libs)
sudo cmake --install build

# Fix ownership after install
sudo chown -R $USER:$USER ~/.config/quickshell/caelestia
```

## Running the Shell

```bash
# Via caelestia-cli (preferred)
caelestia shell -d

# Direct quickshell
qs -c caelestia
```

## Architecture

### Entry Point
- `shell.qml` - Root component, loads Background, Drawers, AreaPicker, Lock, Shortcuts, BatteryMonitor, IdleMonitors

### Directory Structure
| Directory | Purpose |
|-----------|---------|
| `modules/` | Main UI modules (bar, launcher, dashboard, lock, etc.) |
| `components/` | Reusable QML components (controls, effects, containers) |
| `services/` | Singleton services (Audio, Brightness, Network, Colours, etc.) |
| `config/` | Configuration system - reads from `~/.config/caelestia/shell.json` |
| `plugin/` | C++ native plugins compiled as Qt6 QML modules |
| `utils/` | Utility functions and scripts |
| `assets/` | Static assets (images, shaders, PAM configs) |

### Key Patterns

**Singletons:** Services in `services/` and `config/Config.qml` are singletons accessible throughout the shell via `import "services"` or `import "config"`.

**Configuration:** All user settings flow through `config/Config.qml` which reads/writes `~/.config/caelestia/shell.json`. Individual config objects (BarConfig, LauncherConfig, etc.) define defaults and structure.

**Drawer System:** `modules/drawers/` manages slide-out panels (sidebar, dashboard, launcher, etc.) with unified visibility and gesture handling.

**Colours:** `services/Colours.qml` provides the M3 (Material 3) color palette with support for light/dark modes and transparency layers.

### C++ Plugin Modules
Located in `plugin/src/Caelestia/`:
- **Caelestia** - Core utilities (Qalculator, Toaster, ImageAnalyser, AppDb, Requests)
- **Caelestia.Internal** - Hyprland integration, login manager, caching
- **Caelestia.Models** - File system model for file dialogs
- **Caelestia.Services** - Audio visualization (CAVA, PipeWire, beat tracking)

### IPC
Shell exposes IPC via `caelestia shell <target> <function>`. Targets include: `drawers`, `notifs`, `lock`, `mpris`, `picker`, `wallpaper`.

## Configuration

User config: `~/.config/caelestia/shell.json` (not created by default)

Key paths:
- Profile picture: `~/.face`
- Wallpapers: `~/Pictures/Wallpapers/` (configurable via `paths.wallpaperDir`)
- Hyprland user config: `~/.config/caelestia/hypr-user.conf`

## Updating from Upstream

```bash
# Fetch latest upstream changes (also updates 'base' branch)
git fetch upstream

# Merge upstream changes into main
git checkout main
git merge upstream/main

# Alternatively, rebase to keep linear history
git rebase upstream/main
```

**Note:** The `base` branch automatically tracks `upstream/main`, so after `git fetch upstream`, you can use `git diff base..main` to see how your customizations compare to the latest upstream.

---

## AGS Bar Reference (Features to Port)

The previous system bar is at `~/.config/ags/` - an AGS (Astal GTK Shell) implementation using TypeScript/TSX with GTK3. Several features from this bar should be ported to Caelestia's QML/Qt6 architecture.

### AGS Directory Structure
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

### Features to Port

| Feature | AGS Location | Priority | Notes |
|---------|--------------|----------|-------|
| **Workspace App Icons** | `bar/modules/workspaces/AppIcons.tsx` | High | Shows running app icons per workspace; handles grouped windows, swallowed clients, click-to-focus |
| **Available Updates** | `bar/widget/AvailableUpdates.tsx` | Medium | Polls pacman/AUR/flatpak updates via `check-available-updates.sh`; shows count with tooltip breakdown |
| **Kanata Status** | `bar/modules/Kanata.tsx` | Medium | Shows keyboard remapper status; listens to Hyprland custom events `kanata-configuration-switched` |
| **Submap Indicator** | `bar/widget/SubmapStatusIndicator.tsx` | Medium | Shows current Hyprland submap (keybind modes like "groups", "groups-move-in") |
| **System Info** | `bar/modules/SystemInfo.tsx` | Low | RAM/CPU/GPU monitoring widgets (Caelestia already has similar in dashboard) |
| **Icon Resolver** | `lib/icon-resolver/` | Medium | Resolves window class → app icon; special handling for terminal apps showing nested process icons |

### Technology Translation Guide

| AGS (TypeScript/GTK3) | Caelestia (QML/Qt6) |
|-----------------------|---------------------|
| `Variable(value)` | `property var` or `QtObject` with properties |
| `bind(variable)` | QML property bindings |
| `Variable.poll(interval, cmd)` | `Timer` + `Process` from Quickshell.Io |
| `widget.hook(hyprland, "event", ...)` | `Connections` to Hyprland service |
| `exec(cmd)` / `subprocess(cmd)` | `Process { command: [...] }` |
| GTK `<box>`, `<label>`, `<button>` | QML `Row/Column`, `Text`, `MouseArea` |
| SCSS styling | QML inline properties or Caelestia's `Colours` service |

### Key Implementation Notes

**Workspace App Icons:** The AGS implementation uses `hyprctl clients -j` to get window list, filters by workspace, handles swallowed windows (terminal window swallowing), and sorts by screen position. The icon resolver checks `.desktop` files and has special terminal app detection.

**Available Updates Script:** Located at `~/.config/ags/bar/scripts/check-available-updates.sh` - outputs JSON with pacman, AUR, flatpak counts. Can be reused directly.

**Hyprland Custom Events:** AGS listens for custom events via `hyprctl dispatch submap` and `hyprctl dispatch custom`. Caelestia's `services/Hypr.qml` should already support this pattern.
