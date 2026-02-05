# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Symmetria Shell is a Quickshell-based desktop shell for Hyprland. It provides a complete desktop UI including bar, launcher, dashboard, notifications, lock screen, and control center. This is a fork of caelestia-dots/shell for personal customization.

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
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/ -DINSTALL_QSCONFDIR=$HOME/.config/quickshell/symmetria

# Build
cmake --build build

# Install (requires sudo for system libs)
sudo cmake --install build

# Fix ownership after install
sudo chown -R $USER:$USER ~/.config/quickshell/symmetria
```

## Running the Shell

```bash
# Via symmetria-cli (preferred)
symmetria shell -d

# Direct quickshell
qs -c symmetria
```

## Architecture

### Entry Point
- `shell.qml` - Root component, loads Background, Drawers, AreaPicker, Askpass, HyprWhspr, Lock, Shortcuts, BatteryMonitor, IdleMonitors

### Directory Structure
| Directory | Purpose |
|-----------|---------|
| `modules/` | Main UI modules (bar, launcher, dashboard, lock, etc.) |
| `components/` | Reusable QML components (controls, effects, containers) |
| `services/` | Singleton services (Audio, Brightness, Network, Colours, etc.) |
| `config/` | Configuration system - reads from `~/.config/symmetria/shell.json` |
| `plugin/` | C++ native plugins compiled as Qt6 QML modules |
| `utils/` | Utility functions and scripts |
| `assets/` | Static assets (images, shaders, PAM configs) |

### Key Patterns

**Singletons:** Services in `services/` and `config/Config.qml` are singletons accessible throughout the shell via `import "services"` or `import "config"`.

**Configuration:** All user settings flow through `config/Config.qml` which reads/writes `~/.config/symmetria/shell.json`. Individual config objects (BarConfig, LauncherConfig, etc.) define defaults and structure.

**Drawer System:** `modules/drawers/` manages slide-out panels (sidebar, dashboard, launcher, etc.) with unified visibility and gesture handling.

**Colours:** `services/Colours.qml` provides the M3 (Material 3) color palette with support for light/dark modes and transparency layers.

### QML Type Naming Convention (CRITICAL)

**⚠️ Type Name Collisions Break the Shell Silently**

When multiple directory imports export QML types with the same name, **the last import wins**. This can cause catastrophic failures where entire modules are silently replaced by unrelated components.

**The Problem:**
```qml
// In shell.qml:
import "modules/background"    // Has Background.qml (wallpaper display)
import "modules/keycaster"     // Has Background.qml (drawer shape)

Background {}  // ❌ Resolves to keycaster's Background, not wallpaper!
```

**Naming Rules for Module Files:**

| File Purpose | Naming Pattern | Example |
|--------------|----------------|---------|
| Root module entry | `ModuleName.qml` | `Keycaster.qml` |
| Module-specific backgrounds | `ModuleNameBackground.qml` | `KeycasterBackground.qml` |
| Module-specific wrappers | `Wrapper.qml` (OK - not imported in shell.qml) | `Wrapper.qml` |
| Content components | `Content.qml` (OK - not imported in shell.qml) | `Content.qml` |

**Safe Names** (used internally, not exported to shell.qml):
- `Wrapper.qml`, `Content.qml`, `Item.qml` - OK within modules
- These are only referenced via qualified imports like `KeycasterModule.Wrapper`

**Dangerous Names** (export to shell.qml scope):
- `Background.qml` - Conflicts with `modules/background/Background.qml`
- `Launcher.qml` - Conflicts with `modules/launcher/Launcher.qml`
- Any name matching a root module in shell.qml imports

**When Adding New Modules:**
1. Check shell.qml for all directory imports
2. List all `.qml` files in those directories
3. Ensure your new module's files don't share names with any of them
4. Prefix module-specific components: `{ModuleName}{Component}.qml`
5. Run the conflict checker: `./scripts/check-qml-conflicts.sh`

**Automated Detection:**
```bash
# Check for type name conflicts before running the shell
./scripts/check-qml-conflicts.sh

# Exit code 0 = no critical issues (warnings OK)
# Exit code 1 = critical conflicts found (must fix)
```

### Focus Management in Drawers

Keyboard-interactive drawers (Launcher, Clipboard, Askpass, Session) use the `FocusManager` component to handle:
1. **Normal open flow** - Focus the correct element when drawer opens
2. **Pre-loading edge case** - Prevent focus stealing when Loader pre-loads hidden content

**Using FocusManager:**
```qml
import qs.components.misc

Item {
    required property PersistentProperties visibilities

    FocusManager {
        active: root.visibilities.drawerName
        target: focusTarget
        onClose: () => focusTarget.text = ""  // Optional cleanup
    }

    SomeComponent {
        id: focusTarget
    }
}
```

**FocusManager Properties:**
| Property | Type | Description |
|----------|------|-------------|
| `active` | bool | Bind to drawer visibility state |
| `target` | Item | Element to focus when active becomes true |
| `onOpen` | var | Optional callback after focus is set |
| `onClose` | var | Optional callback when drawer closes |

**Dynamic Targets:** For tab-dependent focus (like Clipboard), use a conditional binding:
```qml
FocusManager {
    active: root.visibilities.clipboard
    target: currentTab === 0 ? search : imageNavFocus
}
```

**Reference Implementations:**
| Module | Focus Target | Notes |
|--------|--------------|-------|
| Launcher | Search TextField | Has `onClose` to clear text; separate handler for session-close refocus |
| Clipboard | Search or ImageNavFocus | Dynamic target based on tab; `onOpen`/`onClose` for ref counting |
| Askpass | Dialog container | Simple usage |
| Session | Logout button | Simple usage |

### Panel Background Components

The drawer system uses `ShapePath` components in `modules/drawers/Backgrounds.qml` to render panel backgrounds with "union" corner effects that create smooth visual connections between panels and the shell border/bar.

#### Reusable Components

Located in `components/shapes/`:

| Component | Purpose | Union Corners | Used By |
|-----------|---------|---------------|---------|
| `TopHangingBackground` | Panels hanging from bar/top | TL, TR | Bar Popouts, Askpass, Session, OSD |
| `BottomUpBackground` | Panels rising from bottom | BL, BR | Launcher, Clipboard, Dashboard |

**Edge-case panels** (Sidebar, Notifications, Utilities) have inter-panel dependencies and use custom implementations.

#### Using the Components

```qml
import qs.components.shapes

// Simple usage (default rounding from Config.border.rounding)
BottomUpBackground {
    wrapper: root.panels.launcher
    startX: (shape.width - wrapper.width) / 2 - rounding
    startY: shape.height
}

// Custom rounding (e.g., for detached bar popouts)
TopHangingBackground {
    wrapper: root.panels.popouts
    customRounding: wrapper.isDetached ? Appearance.rounding.normal : Config.border.rounding
    startX: wrapper.x - rounding
    startY: wrapper.y
}
```

#### Component Properties

| Property | Type | Description |
|----------|------|-------------|
| `wrapper` | Item | **Required.** Source of width/height for the panel |
| `customRounding` | real | Override Config.border.rounding (-1 uses default) |
| `customFillColor` | color | Override Colours.generalBackgroundOpaque |
| `rounding` | real | **Read-only.** Computed rounding for startX/startY calculations |
| `roundingY` | real | **Read-only.** Adaptive Y-radius for short panels |

#### Creating a New Panel Background

1. **Identify panel orientation:** Does it hang from top or rise from bottom?
2. **Choose component:** `TopHangingBackground` or `BottomUpBackground`
3. **Set startX/startY in Backgrounds.qml:** Use `rounding` for positioning

**Standard startX/startY patterns:**
| Orientation | startX | startY |
|-------------|--------|--------|
| Top-hanging, centered | `(shape.width - wrapper.width) / 2 - rounding` | `0` |
| Bottom-up, centered | `(shape.width - wrapper.width) / 2 - rounding` | `shape.height` |
| Bottom-up, left-aligned | `rounding` | `shape.height` |
| Top-hanging, positioned | `wrapper.x - rounding` | `wrapper.y` |

#### Technical Details

The components use `ShapePath` with different path directions:
- **TopHangingBackground:** Clockwise path, union arcs at TL/TR (no `direction`), standard arcs at BL/BR (`Counterclockwise`)
- **BottomUpBackground:** Counterclockwise path, union arcs at BL/BR (`Counterclockwise`), standard arcs at TL/TR (no `direction`)

Both include adaptive `roundingY` to prevent rendering artifacts when panel height < rounding * 2.

**Bar Pill Pattern:** Bar components can be grouped into glassmorphism "pill" containers for visual cohesion. The base component `PillContainer.qml` provides:
- `StyledRect` with `Colours.glassmorphism(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)`
- `radius: Appearance.rounding.full` for pill shape
- `pillPadding` constant for internal spacing
- `WrappedLoader` component with `name` property for child elements (enables popout detection)
- `customWidth` property for special width calculations (used by StatusIcons)

Current pills:
| Component | Base | Contents | Color | Popouts |
|-----------|------|----------|-------|---------|
| `StatusIcons.qml` | PillContainer | Audio, Network, Bluetooth, Battery | m3secondary | Yes |
| `Tray.qml` | StyledRect | System tray items | m3surfaceContainerHigh | Yes |
| `TimePill.qml` | PillContainer | Clock, Date | m3tertiary | Planned (calendar) |
| `SystemPill.qml` | PillContainer | CPU, RAM, Updates | m3tertiary | No |

Note: `Tray.qml` doesn't use PillContainer due to unique requirements (conditional styling, compact mode, expand/collapse).

To create a new pill:
1. Extend `PillContainer` and set `colour`, `iconContainer` (optional), `visible` binding
2. Add `RowLayout` with padding spacers and `PillContainer.WrappedLoader` children
3. Register in `Bar.qml`: add to `hasPillMargins`, switch case, and Component definition

### C++ Plugin Modules
Located in `plugin/src/Symmetria/`:
- **Symmetria** - Core utilities (Qalculator, Toaster, ImageAnalyser, AppDb, Requests)
- **Symmetria.Internal** - Hyprland integration, login manager, caching
- **Symmetria.Models** - File system model for file dialogs
- **Symmetria.Services** - Audio visualization (CAVA, PipeWire, beat tracking)

### IPC
Shell exposes IPC via `symmetria shell <target> <function>`. Targets include: `drawers`, `notifs`, `lock`, `mpris`, `picker`, `wallpaper`, `askpass`.

### Askpass (sudo Password Prompt)

The askpass module (`modules/askpass/`) provides a native password prompt for `sudo -A` operations, replacing external tools like rofi.

**Setup:**
```bash
# Add to ~/.zshrc (or ~/.bashrc)
export SUDO_ASKPASS="$HOME/.dotfiles/scripts/symmetria-askpass.sh"
```

**How it works:**
1. When `sudo -A` is invoked, it runs `symmetria-askpass.sh`
2. The script creates a secure FIFO (named pipe) and triggers the shell popup via IPC
3. The native Symmetria dialog appears with password input (animated dots)
4. On submit, password is written to FIFO and read by the script
5. Script outputs password to stdout for sudo

**IPC:** `qs -c symmetria ipc call askpass prompt "<message>" "<fifo_path>"`

**Security:**
- Password never touches disk (FIFO exists only in kernel memory)
- FIFO created with 600 permissions (owner only)
- Shell escaping prevents command injection
- Trap ensures FIFO cleanup on exit

**Keyboard shortcuts:**
| Key | Action |
|-----|--------|
| Enter | Submit password |
| Escape | Cancel (fails sudo) |
| Ctrl+Backspace | Clear password |

**Files:**
- `modules/askpass/Askpass.qml` - Module entry with IPC handler
- `modules/askpass/AskpassWindow.qml` - Overlay dialog (based on WirelessPasswordDialog pattern)
- `~/.dotfiles/scripts/symmetria-askpass.sh` - Wrapper script for sudo

### HyprWhspr (Speech-to-Text Drawer)

The HyprWhspr module (`modules/hyprwhspr/`) provides a native drawer overlay for the HyprWhspr speech-to-text system. The drawer auto-shows when HyprWhspr becomes active and displays state-based UI throughout the transcription lifecycle.

**Prerequisites:**
- HyprWhspr must be installed and configured
- State files at `~/.config/hyprwhspr/`:
  - `visualizer_state` - Current state (recording, paused, processing, error, success)
  - `audio_level` - Float 0.0-1.0 (updated during recording)
  - `recording_control` - FIFO for commands

**State Machine:**

| State | Description | UI Response |
|-------|-------------|-------------|
| `recording` | User is speaking | Animated audio level bars |
| `paused` | Recording paused | Frozen audio bars + pause icon (amber) |
| `processing` | Transcribing audio | CircularIndicator spinner |
| `error` | Transcription failed | Error icon + hint text |
| `success` | Transcription complete | Checkmark icon, auto-hide after delay |

**How it works:**
1. HyprWhspr writes state to `~/.config/hyprwhspr/visualizer_state`
2. `HyprWhsprService` uses `inotifywait` for efficient file-change detection (not polling)
3. State is read directly from file content (`recording`, `paused`, `processing`, `error`, `success`)
4. File deletion signals return to `idle` state
5. Audio level bars animate during recording (polled at 60fps from `audio_level` file)
6. On `success` state, drawer auto-hides after configurable delay

**Configuration (`~/.config/symmetria/shell.json`):**
```json
{
  "hyprwhspr": {
    "enabled": true,
    "autoHideDelay": 1500
  }
}
```

**Files:**
- `services/HyprWhsprService.qml` - Singleton service (state file watcher)
- `modules/hyprwhspr/HyprWhspr.qml` - Root component (auto-show logic)
- `modules/hyprwhspr/Wrapper.qml` - Animation wrapper (top-hanging)
- `modules/hyprwhspr/Content.qml` - State-based UI content
- `modules/hyprwhspr/HyprWhsprBackground.qml` - Background shape
- `config/HyprWhsprConfig.qml` - Configuration defaults

**Note:** Unlike Askpass (IPC-triggered), HyprWhspr uses file-based state watching. The drawer doesn't capture keyboard focus since the user is dictating via voice.

### Clipboard Manager

The clipboard manager (`modules/clipboard/`) provides clipboard history via integration with `cliphist`.

**Prerequisites:**
```bash
paru -S cliphist wl-clipboard
```

Add to Hyprland config:
```conf
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store
```

**Keyboard Shortcuts (when drawer is open):**

| Key | Action |
|-----|--------|
| ↑/↓ | Navigate entries |
| Enter | Restore selected entry to clipboard |
| Escape | Close drawer |

**Toggle keybind:** `Super+V` (configurable in `~/.config/hypr/keybindings.conf`)

**IPC:** `qs -c symmetria ipc call drawers toggle clipboard`

**Clear All:** Click the trash icon twice within 2 seconds to confirm.

**Search vs Highlighting Algorithm:**
- Search uses FZF fuzzy matching (when `useFuzzy: true`) or substring (when `false`)
- Highlighting always uses simple substring matching for simplicity
- Known limitation: With fuzzy search enabled, matched items may not show highlights
  (e.g., "fle" matches "file example" via FZF, but no "fle" substring to highlight)
- Current config has `useFuzzy: false`, so search and highlighting are aligned

### Calculator Drawer

The calculator drawer (`modules/calculator/`) provides a persistent calculation history with live expression evaluation using `libqalculate` via the Symmetria C++ plugin.

**Features:**
- Live evaluation as you type (real-time results)
- Persistent history across shell restarts (stored in `~/.local/state/symmetria/calculator.json`)
- Maximum 50 history entries (configurable)
- Click history entries to reload expressions into input
- Optional auto-copy result to clipboard on Enter

**Keyboard Shortcuts (when drawer is open):**

| Key | Action |
|-----|--------|
| Enter | Add calculation to history, clear input |
| Escape | Close calculator drawer |
| ↑ (Up arrow) | Load most recent history entry into input |
| Ctrl+C | Copy current result (when no text selected) |

**Toggle keybind:** `Super+Shift+C` (add to `~/.config/hypr/keybindings.conf`)

```conf
bind = $mainMod SHIFT, C, exec, qs -c symmetria ipc call drawers toggle calculator
```

**IPC:** `qs -c symmetria ipc call drawers toggle calculator`

**Launcher Integration:** Type `>calc 2+2` in the launcher to open the calculator drawer with the expression pre-filled.

**Clear History:** Click the trash icon twice within 2 seconds to confirm.

**Configuration (`~/.config/symmetria/shell.json`):**
```json
{
  "calculator": {
    "enabled": true,
    "maxHistory": 50,
    "copyOnEnter": false,
    "sizes": {
      "width": 450,
      "historyItemHeight": 40,
      "maxVisibleHistory": 8
    }
  }
}
```

**Files:**
| File | Purpose |
|------|---------|
| `services/Calculator.qml` | Singleton: state management, persistence, Qalculator integration |
| `modules/calculator/Wrapper.qml` | Drawer lifecycle, animations, pre-loading |
| `modules/calculator/Content.qml` | Main UI: history list, result display, input field |
| `modules/calculator/HistoryItem.qml` | Individual history entry component |
| `modules/calculator/CalculatorBackground.qml` | Background shape (uses BottomUpBackground) |
| `config/CalculatorConfig.qml` | Configuration defaults |

**Supported Expressions:** All `libqalculate` syntax including:
- Basic arithmetic: `2+2`, `10/3`, `2^8`
- Functions: `sqrt(144)`, `sin(45deg)`, `log(100)`
- Unit conversions: `5km to miles`, `100F to C`
- Constants: `pi`, `e`, `c` (speed of light)

## Configuration

### Two-Layer System

| Layer | Location | Purpose |
|-------|----------|---------|
| QML defaults | `config/*.qml` | Structure, schemas, defaults (version-controlled) |
| JSON overrides | `~/.config/symmetria/shell.json` | User preferences (NOT version-controlled) |

**⚠️ Key Gotcha:** JSON overrides always win. If you edit a QML default but the value exists in shell.json, your change won't take effect. Check shell.json first when debugging config issues.

### What's Controlled Where

| Control | Location | How to Change |
|---------|----------|---------------|
| Bar layout (entries order) | `config/BarConfig.qml` only | Edit QML directly |
| User preferences | `shell.json` | Control center UI or edit JSON |

### Key Paths
- User config: `~/.config/symmetria/shell.json`
- Profile picture: `~/.face`
- Wallpapers: `~/Pictures/Wallpapers/` (configurable via `paths.wallpaperDir`)
- Hyprland user config: `~/.config/symmetria/hypr-user.conf`

### Custom Color Scheme (Deviation from Upstream)

**Note:** The color scheme path has been customized from upstream for version control.

| Location | Path |
|----------|------|
| QML reads from | `config/color-scheme.json` (version-controlled) |
| CLI writes to | `~/.local/state/symmetria/scheme.json` (not connected) |

**Implication:** CLI commands like `symmetria scheme set` won't affect the shell. The custom warm-neutral scheme is tracked in git.

**To restore CLI compatibility:** See [GitHub Issue #2](https://github.com/CaceresCallieri/symetria-shell/issues/2) for symlink solution.

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

The previous system bar is at `~/.config/ags/` - an AGS (Astal GTK Shell) implementation using TypeScript/TSX with GTK3. Several features from this bar should be ported to Symmetria's QML/Qt6 architecture.

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
| **System Info** | `bar/modules/SystemInfo.tsx` | Low | RAM/CPU/GPU monitoring widgets (Symmetria already has similar in dashboard) |
| **Icon Resolver** | `lib/icon-resolver/` | Medium | Resolves window class → app icon; special handling for terminal apps showing nested process icons |

### Technology Translation Guide

| AGS (TypeScript/GTK3) | Symmetria (QML/Qt6) |
|-----------------------|---------------------|
| `Variable(value)` | `property var` or `QtObject` with properties |
| `bind(variable)` | QML property bindings |
| `Variable.poll(interval, cmd)` | `Timer` + `Process` from Quickshell.Io |
| `widget.hook(hyprland, "event", ...)` | `Connections` to Hyprland service |
| `exec(cmd)` / `subprocess(cmd)` | `Process { command: [...] }` |
| GTK `<box>`, `<label>`, `<button>` | QML `Row/Column`, `Text`, `MouseArea` |
| SCSS styling | QML inline properties or Symmetria's `Colours` service |

### Key Implementation Notes

**Workspace App Icons:** The AGS implementation uses `hyprctl clients -j` to get window list, filters by workspace, handles swallowed windows (terminal window swallowing), and sorts by screen position. The icon resolver checks `.desktop` files and has special terminal app detection.

**Available Updates Script:** Located at `~/.config/ags/bar/scripts/check-available-updates.sh` - outputs JSON with pacman, AUR, flatpak counts. Can be reused directly.

**Hyprland Custom Events:** AGS listens for custom events via `hyprctl dispatch submap` and `hyprctl dispatch custom`. Symmetria's `services/Hypr.qml` should already support this pattern.
