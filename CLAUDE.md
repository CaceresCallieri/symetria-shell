# CLAUDE.md

> **Principle: No duplicate sources of truth.** This document contains ONLY information that cannot be discovered by reading the codebase. For implementation details, read the actual source files — they are the single source of truth.

## Project Overview

Symmetria Shell is a Quickshell-based desktop shell for Hyprland — a fork of [caelestia-dots/shell](https://github.com/caelestia-dots/shell) for personal customization.

**Do NOT use Chrome DevTools MCP tools** — this is a native Wayland desktop shell, not a web application. Use `grim` for screenshots.

**Do NOT start, restart, or kill the shell process.** The user runs Symmetria as their active desktop shell. **NEVER run `qs -c symmetria`, `symmetria shell`, or any launch command** — not even for diagnostics. After QML/asset changes, clear the cache and inform the user that a restart is needed:
```bash
rm -rf ~/.cache/quickshell/qmlcache
# Let the user restart manually
```

**Process management:** The QuickShell binary is `qs`, NOT `quickshell`. To kill: `pkill qs`. To check: `pgrep -fa qs | grep -v grep | grep -v zsh | grep -v python | grep -v claude`. Using `pkill quickshell` or `pgrep quickshell` does NOTHING — the process name is `qs`.

## Build & Run

**QML / SVG / Asset changes** — no compilation needed:
```bash
rm -rf ~/.cache/quickshell/qmlcache
symmetria shell -d
```

**C++ plugin changes** (`plugin/src/`):
```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/ -DINSTALL_QSCONFDIR=$HOME/.config/quickshell/symmetria
cmake --build build
sudo cmake --install build
sudo chown -R $USER:$USER ~/.config/quickshell/symmetria
rm -rf ~/.cache/quickshell/qmlcache
```

**External plugin dependency: `Symmetria.FileManager.Models`** — The file dialog, wallpaper grid, and appearance pane import `Symmetria.FileManager.Models` (FileSystemModel) from the Symmetria File Manager project. This plugin must be built and installed separately:
```bash
cd ~/projects/symmetria-file-manager && ./build-plugin.sh
```
If missing, Symmetria will fail to load components that browse the filesystem. See symmetria-file-manager's CLAUDE.md for build details.

**CLI (`symmetria-cli`)** — Python CLI at `~/.config/quickshell/symmetria-cli/` providing screenshot, recording, scheme, wallpaper, and shell IPC commands. Installed manually (not via pacman):
- Source: `~/.config/quickshell/symmetria-cli/src/symmetria/`
- Installed to: `/usr/lib/python3.14/site-packages/symmetria/`
- Entry point: `/usr/bin/symmetria` (Python 3.14 shim)
- After editing CLI source, re-deploy:
```bash
sudo cp -r ~/.config/quickshell/symmetria-cli/src/symmetria /usr/lib/python3.14/site-packages/symmetria
```

## Pre-commit Hooks

Pre-commit hooks run `qmllint` on `.qml` files and `shellcheck` on `.sh` files. Setup (once per clone):
```bash
git config core.hooksPath .githooks
```
Requires: `qmllint` (ships with Qt) and `shellcheck` (`paru -S shellcheck`).

## Branch Structure

| Branch | Purpose | Tracks |
|--------|---------|--------|
| `main` | Active development with customizations | `origin/main` |
| `base` | Original upstream shell code (reference) | `upstream/main` |
| `feature/*` | Feature branches for significant changes | — |

```bash
git diff base..main          # See all customizations vs original
git log base..main --oneline # Commits that diverge from upstream
git fetch upstream           # Update base (tracks upstream/main)
```

## Architecture

**Entry point:** `shell.qml` — loads `BackgroundModule.Wrapper`, `DrawersModule.Wrapper`, `AreaPickerModule.Wrapper`, Askpass, Stt, Lock, Shortcuts, BatteryMonitor, IdleMonitors.

| Directory | Purpose |
|-----------|---------|
| `modules/` | Main UI modules (bar, launcher, dashboard, lock, etc.) |
| `components/` | Reusable QML components (controls, effects, containers) |
| `services/` | Singleton services (Audio, Brightness, Network, Colours, etc.) |
| `config/` | Configuration system — reads `~/.config/symmetria/shell.json` |
| `plugin/` | C++ native plugins (Symmetria, Symmetria.Internal, Symmetria.Services) — note: Models moved to Symmetria File Manager |
| `utils/` | Utility functions and scripts |
| `assets/` | Static assets (images, shaders, PAM configs) |

**Key patterns:**
- **Singletons** — Services and Config are singletons: `import "services"` / `import "config"`
- **Configuration** — All settings flow through `config/Config.qml` → `~/.config/symmetria/shell.json`
- **Module entry points** — Each major module exposes `Wrapper.qml` as its entry point, imported via qualified alias: `import "modules/x" as XModule` → `XModule.Wrapper {}`. This avoids the last-import-wins collision pitfall. Modules without collision risk (e.g., `Stt`, `Keycaster`) keep their own name.
- **Drawer system** — `modules/drawers/` manages slide-out panels with unified visibility and gestures
- **Colours** — `services/Colours.qml` provides M3 color palette with light/dark + transparency support
- **IPC** — `symmetria shell <target> <function>` (targets: drawers, notifs, lock, mpris, picker, wallpaper, askpass, stt, chords, agentbar)


## Remote Agents (SSH Tunnel)

Symmetria can display agents from remote machines that tunnel their orchestrator socket over SSH. Detection is automatic: the bridge (`scripts/agent-bridge.py`) checks whether each connecting client's `nvim_pid` exists in local `/proc`. If it doesn't, the agent is marked `remote: true` and routed to a separate cloud-icon slot in the merged bar (or shown with a cloud badge in the non-merged bar).

**Setup on the remote machine:**

1. Forward the bridge socket over SSH:
   ```bash
   ssh -R /run/user/$UID/symmetria-agents-remote.sock:/run/user/$UID/symmetria-agents.sock user@host
   ```
   Or add to `~/.ssh/config` as `RemoteForward`.

2. Set `SYMMETRIA_AGENT_SOCKET` in the remote shell environment so hook scripts find the forwarded socket:
   ```bash
   export SYMMETRIA_AGENT_SOCKET=/run/user/$UID/symmetria-agents-remote.sock
   ```

**Known limitation:** If a remote client's `nvim_pid` coincidentally matches a running local process, the bridge will treat it as a local agent (false-negative). This is negligible in practice given the large Linux PID space, but means the remote cloud badge won't appear for that agent.

## Configuration

| Layer | Location | Purpose |
|-------|----------|---------|
| QML defaults | `config/*.qml` | Structure, schemas, defaults (version-controlled) |
| JSON overrides | `~/.config/symmetria/shell.json` | User preferences (NOT version-controlled) |

**JSON overrides always win.** If you edit a QML default but the value exists in shell.json, your change won't take effect. Check shell.json first when debugging config issues.

**Key paths:**
- User config: `~/.config/symmetria/shell.json`
- Profile picture: `~/.face`
- Wallpapers: `~/Pictures/Wallpapers/` (configurable via `paths.wallpaperDir`)
- Hyprland user config: `~/.config/symmetria/hypr-user.conf`

**Color scheme:** QML reads from `~/.local/state/symmetria/scheme.json` (the same file the CLI writes to). On first launch, `Colours.qml` copies the bundled default from `config/color-scheme.json` to the state path. The version-controlled file serves only as the initial seed template.

## Critical Pitfalls

These are hard-won lessons from past bugs. Each is a brief summary — full explanations with code examples are in the linked docs.

**QML required property shadowing** — `required property string foo` creates a NEW shadow property; `required foo` uses the EXISTING one. Shadowing silently breaks delegate bindings. → `docs/qml-pitfalls.md`

**QML type naming collisions** — When multiple directory imports export the same type name, the last import wins. This silently replaces entire modules. Run `./scripts/check-qml-conflicts.sh` before adding new modules. → `docs/qml-pitfalls.md`

**Transparency compensation** — Components outside the unified `Backgrounds` system appear darker (50% vs 22.5% black). Must manually compute `generalBackgroundAlpha × transparency.base`. → `docs/qml-pitfalls.md`

**XOR mask inversion** — The drawers window input region uses XOR. Expanding `mainRect` SHRINKS the clickable area. The bar must stay OUTSIDE `mainRect` to receive input. → `docs/qml-pitfalls.md`

**Cursor shadowing** — A `visible: true` MouseArea at highest z-order shadows ALL `cursorShape` settings below it, even when `enabled: false`. Overlay MouseAreas need both `enabled` and `visible` guards. → `docs/qml-pitfalls.md`

**Layout sizes in onCompleted** — `Component.onCompleted`, `Qt.callLater()`, and `Timer { interval: 0 }` all fire BEFORE ColumnLayout computes `implicitHeight` (polish phase). Use `onImplicitHeightChanged` for reliable post-polish values. Also: set model item state BEFORE adding to arrays (Repeater creates delegates synchronously). → `docs/qml-pitfalls.md`

**STT target locking** — Window and agent targets are captured once at `start()` and never re-resolved. Re-resolving at stop-time or delivery-time causes wrong-agent delivery because `activeAgentForTerminal()` is identity-unstable. → `docs/stt-design-decisions.md`

**List mutation in loops is O(n²)** — Never `push()` to a QML list property in a loop when computed properties (`.filter()`, `.map()`) bind to it. Each push triggers all bindings. Build a local array, assign once: `root.list = temp`. This caused a 23s startup freeze with 6,890 notifications. → `docs/qml-pitfalls.md`

**Qt HTTP/2 protocol errors** — Qt 6's `QNetworkAccessManager` enables HTTP/2 by default. Some servers (notably `ipinfo.io`) cause silent protocol errors that break the entire weather init chain. Disable per-request with `Http2AllowedAttribute = false`. → `docs/qt-http2-pitfall.md`

**Hypr.activeToplevel null on fresh start** — The Wayland activation guard in `Hypr.qml` may filter out the active toplevel at shell startup before the `activated` protocol event arrives. Fall back to raw `Hyprland.activeToplevel` when you only need Hyprland window identity (address, class, PID) rather than confirmed Wayland activation. → `docs/qml-pitfalls.md`

**Layer-shell focus restoration race** — A layer-shell window with `WlrKeyboardFocus.Exclusive` triggers focus restoration on unmap (wlroots restores whoever held focus before the layer mapped). Synchronous `focuswindow` dispatches lose to the restoration. Always `hide()` first, then `Qt.callLater(() => Hypr.dispatch(...))`. Dispatchers that don't require an active focus target (e.g. `killwindow`) are unaffected. → `docs/qml-pitfalls.md`

**Electron tray icons are unthemeable from QML** — Discord, Heroic, Altus, and other Electron apps all register with SNI id `chrome_status_icon_1` and ship embedded pixmap bytes (no file path). They are indistinguishable from each other at the QML layer because `SystemTrayItem` exposes neither bus name nor PID. Do NOT attempt to auto-theme them via id heuristics — it cannot work. Users must override via `iconSubs` or live with the raw pixmap. → `docs/tray-icon-theming.md`

**Property contract drift across containers** — If a child exposes a property whose value a parent reads in layout calculations (e.g. `Notification.nonAnimHeight` read by `Content.qml` to size the popup stack), that property has an external contract. Refactoring its semantics inside the child (e.g. "moving margins out for cleaner math") silently under-allocates the parent — visible as last-in-stack body clipping. Grep the whole codebase for that property name to find all consumers before changing its semantics; add a comment on or immediately above the property declaration stating the contract, e.g. `// CONTRACT: nonAnimHeight = full card height including margins (read by Content.qml stack)`. → `docs/qml-pitfalls.md`

## Deep Dives

Detailed documentation in `docs/` — read on-demand when working on specific areas:

**Architecture & Extension:**
- [`drawer-extension-guide.md`](docs/drawer-extension-guide.md) — Panel backgrounds, bar pill pattern, FocusManager usage
- [`ags-porting-reference.md`](docs/ags-porting-reference.md) — AGS bar features to port (workspace icons, updates, Kanata, submap)

**Pitfalls & Research:**
- [`qml-pitfalls.md`](docs/qml-pitfalls.md) — All QML gotchas consolidated
- [`cursor-shape-layer-shell.md`](docs/cursor-shape-layer-shell.md) — Cursor shape behavior in Wayland layer-shell
- [`tray-icon-theming.md`](docs/tray-icon-theming.md) — Icon resolution pipeline, Electron SNI limitation, Option C future path
- [`module-setup.md`](docs/module-setup.md) — External prerequisites for Askpass, Clipboard, STT, Calculator, KeyChords

**STT:**
- [`stt-design-decisions.md`](docs/stt-design-decisions.md) — Pipeline design rationale and historical bugs
- [`stt-drawer-animation.md`](docs/stt-drawer-animation.md) — Show animation stutter: root cause, fix, and QML polish lifecycle
- [`PRD-stt-system.md`](docs/PRD-stt-system.md) — Original product requirements
- [`stt-future-work.md`](docs/stt-future-work.md) — Planned improvements

**Investigations:**
- `*.investigation.md` files — Debug session logs for past issues
- [`agent-state-diagnostics.md`](docs/agent-state-diagnostics.md) — Hook → bridge → QML pipeline, stuck-state watchdog, SIGUSR1 dump, `agentbar diagnose` IPC

## Updating from Upstream

```bash
git fetch upstream
git checkout main
git merge upstream/main    # Or: git rebase upstream/main
```

The `base` branch tracks `upstream/main`, so after fetch you can compare: `git diff base..main`.
