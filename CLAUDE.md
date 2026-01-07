# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Caelestia Shell is a Quickshell-based desktop shell for Hyprland. It provides a complete desktop UI including bar, launcher, dashboard, notifications, lock screen, and control center. This is a fork of caelestia-dots/shell for personal customization.

**Upstream:** https://github.com/caelestia-dots/shell

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
git fetch upstream
git merge upstream/main
```
