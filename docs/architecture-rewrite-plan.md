# Symmetria Architecture Rewrite: Modular Satellite Architecture

**Date:** 2026-04-03
**Status:** Planning
**Branch:** investigate/startup-delay (investigation), TBD (implementation)

---

## Motivation: Why This Rewrite Is Necessary

### The Performance Problem

A deep investigation on 2026-04-03 revealed that Symmetria's startup freezes the event loop for **80-93 seconds** on Qt 6.11.0 (upgraded from 6.10.2 on 2026-03-26). Through systematic isolation experiments, we identified the exact bottleneck:

| Test Configuration | Event Loop Freeze |
|---|---|
| Bare Quickshell (no modules) | **504ms** |
| All modules EXCEPT Drawers | **671ms** |
| Drawers with Panels stubbed out | **672ms** |
| **Drawers with Panels (the full cascade)** | **91,092ms** |
| Full shell (all modules) | **92,896ms** |

**Panels.qml alone accounts for 99% of the freeze.** It imports 12 module directories (~160 QML files, ~1,400 property bindings) which are all compiled and evaluated synchronously during Quickshell's reload walk.

### Root Cause: Qt 6.11.0 Regression

The freeze is caused by a **Qt 6.11.0 performance regression** in QML binding evaluation. We confirmed this by:

1. **Building old Quickshell (r67) from source against Qt 6.11** → still 86s (Quickshell version NOT a factor)
2. **Testing identical code on both Qt versions** → 7-10s on Qt 6.10.2, 80-93s on Qt 6.11.0
3. **Testing warm vs. cold QML cache** → both ~90s (cache NOT a factor)
4. **Testing identical code from the fix/deferred-panel-loading branch** → 97s on Qt 6.11 (code changes NOT a factor)

The suspected Qt changes are:
- "Do not store type references for properties" — a `QQmlPropertyCache` internal change enabling cyclic type references, which may make property resolution more expensive
- Property shadowing runtime enforcement (virtual/override/final) — new runtime checking on every property access

**Arch Linux is the only major distro shipping Qt 6.11.0** (as of April 2026). NixOS, Fedora, openSUSE are all on 6.10.x. This is why no one else has reported the issue yet — caelestia's userbase is ~70% NixOS.

### Why Architecture Is the Real Fix

Even on Qt 6.10.2, the shell took **7-10 seconds** to start — still slow. The root problem isn't just Qt 6.11; it's the **monolithic synchronous loading pattern**:

- `Variants` forces synchronous compilation (async Loader inside Variants is a no-op)
- `qs.modules.*` paths don't resolve in URL-loaded files (blocking deferred loading via Loader.setSource)
- Quickshell.Services.Notifications C++ module blocks ~19s during D-Bus registration
- The binding evaluation cascade is **super-linear** — each additional module has outsized impact

A deferred loading approach was attempted (stash@{1}, got 8.8s → 1.0s) but was reverted as over-engineering and had framework limitations. **The correct long-term solution is to not load everything in one process.**

### Additional Benefits Beyond Performance

1. **Development experience** — Change the launcher code, restart only the launcher. No 90-second wait to test a button color change.
2. **Fault isolation** — A crash in the STT system doesn't kill the bar. The user keeps their workspace indicators, clock, and system tray while the failed module can be restarted.
3. **Standalone utility** — `symmetria-clipboard` can run without the shell. Useful for users who only want the clipboard manager, or during development/testing.
4. **Incremental loading** — Modules load on first use. A user who never opens the calculator never pays its compilation cost.
5. **Composability** — Users can mix and match modules. Don't want the packages module? Don't install it.

---

## Architecture Overview

### Current Architecture (Monolithic)

```
qs -c symmetria (ONE process, ONE QML engine)
  └─ shell.qml
       ├─ Background {}
       ├─ Drawers {}                    ← Variants (per-screen)
       │    ├─ StyledWindow
       │    │    ├─ Bar {}              ← imports "popouts" → controlcenter (49 files!)
       │    │    ├─ AgentBar {}
       │    │    ├─ Panels {}           ← imports 12 module dirs (~160 files) ← THE BOTTLENECK
       │    │    │    ├─ Session
       │    │    │    ├─ Launcher
       │    │    │    ├─ Dashboard
       │    │    │    ├─ Clipboard
       │    │    │    ├─ Calculator
       │    │    │    ├─ Askpass
       │    │    │    ├─ STT
       │    │    │    ├─ Packages
       │    │    │    ├─ Utilities
       │    │    │    ├─ Sidebar
       │    │    │    └─ Popouts (controlcenter, windowinfo, calendar)
       │    │    ├─ Backgrounds {}
       │    │    └─ Interactions {}
       │    └─ Visibilities
       ├─ NotificationsOverlay {}       ← Quickshell.Services.Notifications (19s D-Bus block)
       ├─ Askpass {}
       ├─ Stt {}
       ├─ KeyChords {}
       ├─ KeyChordsOverlay {}
       ├─ KillConfirm {}
       ├─ KillConfirmOverlay {}
       ├─ Lock {}
       ├─ Shortcuts {}
       ├─ BatteryMonitor {}
       └─ IdleMonitors {}
```

**Problem:** Everything loads at once. 353 QML files, ~1,400 properties, compiled synchronously.

### Proposed Architecture (Modular Satellites)

```
qs -c symmetria (CORE — lightweight, starts in <1s)
  └─ shell.qml
       ├─ Background {}
       ├─ Drawers {}                    ← Only bar, frame, input mask
       │    ├─ Bar {}                   ← Simplified: no heavy popouts
       │    ├─ AgentBar {}
       │    ├─ DrawerFrame {}           ← Empty frame, receives satellite geometry via IPC
       │    └─ Interactions {}          ← Manages input mask based on satellite reports
       ├─ NotificationsOverlay {}
       ├─ Lock {}
       ├─ Shortcuts {}
       ├─ BatteryMonitor {}
       └─ IdleMonitors {}

qs -c symmetria-launcher (SATELLITE — loads on first open, ~200ms)
  └─ shell.qml
       ├─ Detects: is symmetria shell running?
       │    YES → EmbeddedMode: layer-shell surface inside drawer area
       │    NO  → StandaloneMode: centered overlay window
       └─ LauncherContent {}            ← Same component in both modes

qs -c symmetria-clipboard (SATELLITE — loads on first open)
qs -c symmetria-stt (SATELLITE — loads on trigger)
qs -c symmetria-calculator (SATELLITE — loads on open)
qs -c symmetria-askpass (SATELLITE — loads on sudo)
qs -c symmetria-session (SATELLITE — loads on session menu)
qs -c symmetria-dashboard (SATELLITE — loads on hover/click)
qs -c symmetria-sidebar (SATELLITE — loads on hover/click)
qs -c symmetria-utilities (SATELLITE — loads on hover/click)
qs -c symmetria-packages (SATELLITE — loads on open)
```

---

## Repository Structure

### Monorepo with Symlinks

```
symmetria/                              # Single git repository
├── core/                               # Shared code — THE single source of truth
│   ├── components/                     # StyledRect, Anim, containers, controls, effects...
│   │   ├── controls/
│   │   ├── containers/
│   │   ├── effects/
│   │   └── misc/
│   ├── services/                       # Audio, Brightness, Colours, Network, SttService...
│   ├── config/                         # Config.qml, BarConfig, shell.json schema
│   ├── utils/                          # Utility functions, scripts
│   └── assets/                         # Images, shaders, PAM configs
│
├── shell/                              # Core shell config → installs as qs -c symmetria
│   ├── shell.qml                       # Entry point: bar, background, frame, notifications
│   ├── components → ../core/components # Symlink
│   ├── services → ../core/services     # Symlink
│   ├── config → ../core/config         # Symlink
│   ├── utils → ../core/utils           # Symlink
│   ├── assets → ../core/assets         # Symlink
│   └── modules/
│       ├── bar/                        # Bar (always loaded with shell)
│       ├── agentbar/                   # Agent bar (always loaded)
│       ├── drawers/                    # Drawer frame + input mask (no panel content)
│       ├── background/                 # Wallpaper, focus mode
│       ├── notifications/              # Notification overlay
│       ├── osd/                        # On-screen display
│       ├── lock/                       # Lock screen
│       └── keycaster/                  # Key display overlay
│
├── launcher/                           # App Launcher → qs -c symmetria-launcher
│   ├── shell.qml                       # Entry: mode detection, window setup
│   ├── components → ../core/components
│   ├── services → ../core/services
│   ├── config → ../core/config
│   └── modules/
│       └── launcher/                   # Launcher-specific code (migrated from shell)
│
├── clipboard/                          # Clipboard Manager → qs -c symmetria-clipboard
│   ├── shell.qml
│   ├── components → ../core/components
│   ├── services → ../core/services
│   ├── config → ../core/config
│   └── modules/
│       └── clipboard/
│
├── stt/                                # Speech-to-Text → qs -c symmetria-stt
│   ├── shell.qml
│   ├── components → ../core/components
│   ├── services → ../core/services
│   ├── config → ../core/config
│   └── modules/
│       └── stt/
│
├── askpass/                            # Password Dialog → qs -c symmetria-askpass
├── calculator/                         # Calculator → qs -c symmetria-calculator
├── session/                            # Session Menu → qs -c symmetria-session
├── dashboard/                          # Dashboard → qs -c symmetria-dashboard
├── sidebar/                            # Sidebar → qs -c symmetria-sidebar
├── utilities/                          # Utilities Panel → qs -c symmetria-utilities
├── packages/                           # Package Manager → qs -c symmetria-packages
├── keychords/                          # Key Chords Overlay → qs -c symmetria-keychords
├── killconfirm/                        # Kill Confirmation → qs -c symmetria-killconfirm
│
├── plugin/                             # C++ native plugins (Symmetria.Internal, etc.)
├── scripts/                            # Utility scripts (agent-bridge.py, stt-transcribe.sh, etc.)
└── docs/                               # Documentation
```

### Why Symlinks Work

Quickshell resolves `qs.components`, `qs.services`, `qs.config` relative to the config directory. A symlink at `launcher/components → ../core/components` makes these paths resolve to the shared core code. Zero duplication — every module reads from the same source files.

### Installation

Each module installs to its own Quickshell config directory:
```
~/.config/quickshell/symmetria/         → shell/
~/.config/quickshell/symmetria-launcher/ → launcher/
~/.config/quickshell/symmetria-clipboard/ → clipboard/
...
```

A single install script or Makefile handles symlinking.

---

## IPC Protocol

### Shell → Satellite Communication

When the shell wants to show a satellite:

```
symmetria shell drawers show-satellite launcher \
    --screen eDP-1 \
    --x 0 --y 48 \
    --width 400 --height 900 \
    --theme-path ~/.config/symmetria/shell.json \
    --color-scheme-path config/color-scheme.json
```

Or via a Unix socket / Quickshell IPC:

```json
{
    "type": "show",
    "module": "launcher",
    "screen": "eDP-1",
    "geometry": { "x": 0, "y": 48, "width": 400, "height": 900 },
    "theme": { "transparency": 0.85, "rounding": 12 }
}
```

### Satellite → Shell Communication

Satellites report their state back:

```json
{
    "type": "satellite-state",
    "module": "launcher",
    "visible": true,
    "geometry": { "x": 0, "y": 48, "width": 400, "height": 900 },
    "needsFocus": true
}
```

The shell uses this to:
- Update the XOR input mask (make the satellite's area clickable)
- Manage HyprlandFocusGrab
- Coordinate with other satellites (close launcher when clipboard opens)

### Detection: Is the Shell Running?

Each satellite checks on startup:

```qml
readonly property bool shellRunning: {
    // Option A: Check for shell's IPC socket
    return File.exists("/run/user/1000/quickshell/by-id/symmetria/...")
    // Option B: Check Quickshell.instances (if available)
    // Option C: Check for a known D-Bus name
    // Option D: Try connecting to the IPC socket — if it responds, shell is running
}
```

### Dual-Mode Pattern

Each satellite's shell.qml follows this pattern:

```qml
ShellRoot {
    readonly property bool shellRunning: /* detection logic */

    // Embedded mode: layer-shell surface positioned by the shell
    Loader {
        active: shellRunning
        sourceComponent: EmbeddedWrapper {
            // WlrLayershell at drawer position
            // No window chrome
            // Receives geometry from shell IPC
            LauncherContent { /* the actual UI */ }
        }
    }

    // Standalone mode: own window with controls
    Loader {
        active: !shellRunning
        sourceComponent: StandaloneWrapper {
            // Centered window or layer-shell overlay
            // Own close button, own theme loading
            LauncherContent { /* same UI component */ }
        }
    }
}
```

The key is that `LauncherContent` (the actual functional UI) is shared between both modes. Only the wrapper changes.

---

## Technical Challenges and Solutions

### 1. XOR Input Mask Coordination

**Current:** Drawers.qml uses an XOR Region built from `panels.children` to make the drawer area clickable only where panels exist.

**Satellite approach:** The shell maintains a list of active satellite geometries and builds the XOR mask from those reports.

```qml
// In core shell's Drawers.qml
property var satelliteGeometries: ({})  // populated via IPC

Variants {
    model: Object.values(satelliteGeometries)
    Region {
        required property var modelData
        x: modelData.x; y: modelData.y
        width: modelData.width; height: modelData.height
        intersection: Intersection.Subtract
    }
}
```

### 2. Focus Grab

**Current:** One `HyprlandFocusGrab` in Drawers handles focus for all panels.

**Satellite approach:** Each satellite manages its own focus. Alternatively, the core shell's focus grab includes all satellite windows:

```qml
HyprlandFocusGrab {
    active: anySatelliteNeedsFocus
    windows: [drawersWindow, ...satelliteWindows]  // satellite windows registered via IPC
}
```

This may require Quickshell to support dynamic window lists in HyprlandFocusGrab, or each satellite does its own grab.

### 3. Shared Services (Colours, Config)

**No duplication needed.** Each satellite symlinks to `core/services/` and reads the same `shell.json` and `color-scheme.json` files. The `Colours` singleton in each process reads the same file.

**Live theme updates:** If the user changes the color scheme, each running satellite picks it up via Qt's file system watcher (QML file binding on the config files). Or the shell broadcasts a "theme-changed" IPC event.

### 4. Bar Popouts (Calendar, ControlCenter, WindowInfo)

These are currently the **heaviest cascade** — controlcenter alone is 49 QML files. Options:

- **Option A:** Keep popouts in the core shell but defer their loading (Loader.setSource on first hover). This is feasible because popouts don't live inside Variants — they're content within the bar's popout wrapper.
- **Option B:** Make each popout a satellite. `symmetria-controlcenter`, `symmetria-windowinfo`. Opens as an overlay near the bar pill that triggered it.
- **Option C:** Move popouts to the bar module's internal Loader with relative imports (bypasses qs.modules.* limitation since they're in the same directory tree).

Option A or C is probably simplest for Phase 1.

### 5. Animation Continuity

**Current:** Panel slide-in animations happen within the Drawers window.

**Satellite approach:** The satellite creates its own layer-shell window that animates independently. The shell animates the scrim/backdrop, and the satellite animates its own slide-in. A small IPC latency (~10-50ms) between "shell says show" and "satellite starts animating" may cause a brief visual gap.

**Mitigation:** The shell sends a "prepare" event slightly before showing, giving the satellite time to create its window (but keep it invisible). Then a "show" event triggers the animation in both shell and satellite simultaneously.

### 6. Quickshell.Services.Notifications

This C++ module blocks ~19s during D-Bus registration. In the new architecture, it stays in the core shell but is loaded asynchronously (since it's no longer inside Variants). Or it becomes its own satellite — `symmetria-notifications`.

---

## Migration Plan

### Phase 1: Extract Core (Non-breaking)

1. Create the `core/` directory with shared code (components, services, config, utils, assets)
2. Replace direct directories with symlinks in the current shell config
3. Verify the shell works identically with symlinked core
4. **No architectural change yet** — just reorganization

### Phase 2: Proof of Concept — Extract Askpass

Askpass is the ideal first candidate:
- Small (5 QML files)
- Self-contained (no interaction with other panels)
- Already triggered via IPC (`symmetria shell askpass <password>`)
- Needs to work standalone anyway (sudo without the shell)

Steps:
1. Create `askpass/shell.qml` with dual-mode pattern
2. Move askpass module code to `askpass/modules/askpass/`
3. Implement shell detection (check if symmetria is running)
4. In embedded mode: layer-shell popup positioned near the bar
5. In standalone mode: centered overlay window
6. Update the core shell to launch `qs -c symmetria-askpass` via IPC instead of showing the internal component
7. Remove askpass from core shell's imports

### Phase 3: Extract Calculator, STT

Same pattern as Phase 2. These are medium complexity and relatively self-contained.

### Phase 4: Extract Launcher, Clipboard

Larger modules with more complex interactions (search, history). The dual-mode pattern is the same, but the IPC needs to handle more state (search query, scroll position on re-open).

### Phase 5: Extract Dashboard, Sidebar, Utilities, Session

The drawer panels. These require the most careful work because they interact with the drawer frame's positioning, input mask, and hover zones.

### Phase 6: Extract Bar Popouts

ControlCenter (49 files), WindowInfo, Calendar. These are triggered from bar pills and appear as floating panels. Making them satellites decouples the heaviest import cascade from the bar.

### Phase 7: Core Shell Cleanup

After all panels are extracted:
- Panels.qml is removed entirely (or becomes a thin IPC coordinator)
- Drawers.qml only manages the frame, bar, and satellite geometry
- The core shell starts in <1 second
- Each satellite loads in 100-300ms on first use

---

## Expected Results

### Startup Performance

| Phase | Core Shell Startup | Notes |
|---|---|---|
| Current (monolithic) | **80-93s** (Qt 6.11) | Everything loaded at once |
| Phase 1 (reorganize) | **80-93s** | No architectural change |
| Phase 2-3 (3 satellites) | **~70-80s** | Small reduction |
| Phase 4-5 (8 satellites) | **~10-20s** | Major reduction — only bar popouts cascade remains |
| Phase 6 (popouts extracted) | **< 1s** | Core shell is just bar + frame + background |

### On Qt 6.10.2 (for reference)

| Phase | Core Shell Startup |
|---|---|
| Current | 7-10s |
| Phase 7 complete | < 1s |

### Module Load Times (estimated, per satellite)

| Module | QML Files | Estimated Load Time |
|---|---|---|
| Askpass | 5 | ~100ms |
| Calculator | 4 | ~100ms |
| STT | 7 | ~150ms |
| Clipboard | 8 | ~200ms |
| Launcher | 16 | ~300ms |
| Dashboard | 14 | ~250ms |
| Sidebar | 10 | ~200ms |
| Utilities | 11 | ~200ms |
| Session | 3 | ~100ms |
| Packages | 7 | ~150ms |
| ControlCenter | 49 | ~500ms |

---

## Full Investigation Data (Reference)

### Measurement Methodology

All measurements use a heartbeat Timer in QML that fires every 500ms. The time between `Component.onCompleted` and the first heartbeat reveals the exact event loop freeze duration. Beats arriving at +500ms = instant startup. Beats arriving at +90000ms = 90-second freeze.

```qml
Component.onCompleted: console.log("[BOOT] ShellRoot @ " + Date.now())
Timer {
    interval: 500; running: true; repeat: true; property int b: 0
    onTriggered: {
        b++;
        console.log("[BOOT:HB] #" + b + " @ " + Date.now());
        if (b >= 20) running = false;
    }
}
```

Read results with: `qs log -c symmetria -n 2>&1 | grep "\[BOOT"`

### Complete Isolation Test Results (2026-04-03)

| Test | Freeze | Conclusion |
|---|---|---|
| T0: Bare Quickshell | 504ms | Framework baseline |
| T1: Imports only (no instantiation) | 508ms | Imports are free |
| T4: All module imports, no instantiation | 508ms | Confirming imports are free |
| Full shell minus notifications | 92,896ms | Notifications D-Bus is overlapped |
| Drawers only | 91,092ms | Drawers = 99% of freeze |
| Everything except Drawers | 671ms | All other modules = ~170ms |
| Drawers with stubbed Panels | 672ms | Panels = 99% of Drawers |
| fix/deferred-panel-loading branch (identical Panels) | 97,301ms | Code changes NOT a factor |
| Warm cache (no cache clear) | 93,460ms | Cache NOT a factor |
| Old Quickshell r67 + Qt 6.11 (built from source) | 85,558ms | Quickshell version NOT a factor |

### Qt Version Correlation

| Date | Qt Version | Quickshell | Delay |
|---|---|---|---|
| 2026-03-06 | 6.10.2-1 | 0.2.0.r67 | **7-10s** |
| 2026-03-26 | **6.11.0-1** | 0.2.0.r110 | *(upgrade day)* |
| 2026-03-29 | 6.11.0-1 | 0.2.0.r110 | **18-20s** |
| 2026-04-03 | 6.11.0-1 | 0.2.0.r110 | **80-93s** |

### Qt 6.11 Distribution Status (April 2026)

Only Arch Linux (and derivatives like CachyOS) ship Qt 6.11.0. All other distros are on 6.10.x or older. Caelestia's userbase is ~70% NixOS (Qt ~6.10.1), so they haven't encountered this yet.

### Benchmark Infrastructure

- Test configs: `~/.config/quickshell/qs-startup-bench/` (symlinked to symmetria's modules)
- Heartbeat profiler: active on `investigate/startup-delay` branch in `shell.qml`
- Old Quickshell build: was at `/tmp/quickshell-build/` (cleaned up)
- Investigation docs: `docs/startup-delay-investigation/` (8 files, committed on investigate/startup-delay)

### Suspected Qt 6.11 Changes

1. **"Do not store type references for properties"** — `QQmlPropertyCache` no longer stores type refs (enables cyclic refs, may slow property resolution)
2. **Property shadowing runtime enforcement** — new `virtual`/`override`/`final` keywords add runtime checking; our logs show `qt.qml.propertyCache.append: Member ... overrides a member of the base object` warnings

---

## Open Questions

1. **Can Hyprland's `HyprlandFocusGrab` include windows from different Quickshell processes?** If not, each satellite needs its own focus management.
2. **What's the IPC latency between Quickshell processes?** This affects animation coordination.
3. **Can `Variants` in the core shell dynamically include satellite windows in its Region mask?** Or does the satellite need to set its own input region?
4. **Should the core shell launch satellites on demand, or should they be systemd user services?** Systemd services would enable auto-restart on crash.
5. **How does Quickshell handle multiple configs accessing the same `shell.json`?** File locking? Concurrent read safety?
6. **Should popouts (controlcenter, windowinfo, calendar) stay in the core shell or become satellites?** They're tightly coupled to bar pill positions.

---

## Related Documents

- `docs/startup-delay-investigation/` — 8-file investigation with profiling methodology, root cause analysis, import cascade map, attempted fixes, Quickshell limitations, test results, and bisect guide
- `docs/startup-delay-investigation/qt-bug-report-draft.md` — Draft Qt bug report
- Memory: `startup-delay-investigation.md` — Condensed findings
- Memory: `feedback_shell_instance_awareness.md` — Always check for running shell before launching test instances
