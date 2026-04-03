# Raw Test Results

All tests on: Arch Linux, kernel 6.19.9-zen1-1-zen, AMD Radeon 860M (radeonsi/krackan1, Mesa 26.0.3), Quickshell 0.2.1 (git 08058326). Single eDP-1 display at 165Hz.

## Isolation Tests (Binary Search)

| Configuration | Heartbeat #1 | Delay |
|---|---|---|
| 0 windows (Lock + IdleMonitors only, all modules commented out) | +507ms | **None** |
| 1 simple PanelWindow (30px red bar) | +513ms | **None** |
| 5 simple empty PanelWindows | +509ms | **None** |
| Bare Drawers (empty StyledWindow, no content) | +512ms | **None** |
| Bare Drawers + Bar + AgentBar (stub Panels, no heavy imports) | +605ms | **None** |
| Bare Drawers + OSD + Askpass + Lock + IdleMonitors | +512ms | **None** |
| Bare Drawers + OSD + Lock + IdleMonitors | +540ms | **None** |
| Bare Drawers + OSD + **NotificationsOverlay** + Lock + IdleMonitors | +19,753ms | **19.2s** |
| Full Drawers (with Panels) + OSD + Askpass + Lock + IdleMonitors (no Notifs) | +18,817ms | **18.7s** |
| Full Drawers + ALL modules except Notifications | +18,562ms | **18.2s** |
| Full shell (original, cold cache) | +17,596ms | **17.4s** |
| Full shell (original, warm cache) | +18,200ms | **18.2s** |

## Module Addition Tests (starting from bare Drawers + Lock + IdleMonitors)

| Added Module | Result |
|---|---|
| + OsdOverlay | Instant |
| + Askpass | Instant |
| + NotificationsOverlay | **19.7s freeze** |
| + Background | When combined with other blockers: same ~18s |
| + Stt | Instant (when alone with bare Drawers) |
| + Keycaster | Instant (when alone with bare Drawers) |
| + KeyChords | Instant (when alone with bare Drawers) |
| + BatteryMonitor | Instant (when alone with bare Drawers) |

## Import-Only Test

Drawers.qml with ALL 12+ module imports but ZERO component creation (bare StyledWindow):
- **Result: 18.9s delay** — proves the import compilation alone causes the freeze

## Deferred Loading Tests

| Approach | Result |
|---|---|
| Loader { asynchronous: true } for DrawersImpl.qml inside Variants | **19.3s** — Variants forces sync |
| LazyLoader { loading: true; source: url } inside Variants | **19.3s** — same |
| Timer { interval: 0 } + setSource inside Variants | **20.1s** — Timer fires, then setSource blocks |
| Loader { source: url } from shell.qml (bypassing directory import) | **0.6s** — INSTANT but `qs.modules.*` paths fail |
| DrawersImpl.qml with relative imports (`../../bar`) | Imports resolve ✓, but Variants blocks anyway |

## Service Initialization Timeline (from full shell startup)

All timestamps relative to first QML init (~T+0):

```
Phase 1: Component Creation (0-106ms)
  +0ms    Hypr.onCompleted
  +1ms    Keycaster.StyledWindow
  +6ms    Wallpapers.onCompleted
  +11ms   NotificationsOverlay.StyledWindow
  +12ms   Brightness.Monitor.onCompleted
  +13ms   Brightness → ddcutil detect STARTS
  +15ms   Audio.onCompleted, OsdOverlay.StyledWindow
  +18ms   AgentService.onCompleted, Recorder.onCompleted
  +25ms   Nmcli.onCompleted + nmcli monitor STARTS
  +29ms   Weather.onCompleted → ipinfo.io request STARTS
  +65ms   Network.onCompleted
  +96ms   Clipboard.onCompleted → "which cliphist" STARTS
  +104ms  Drawers.StyledWindow, Bar, Panels
  +106ms  ShellRoot.onCompleted

Phase 2: File I/O (106-233ms)
  +201ms  Config: shell.json loaded
  +213ms  Hypr: XKB rules base.lst loaded
  +219ms  Colours: color-scheme.json loaded
  +233ms  Wallpapers: FileSystemModel scan (30 images)

★ FROZEN: ~17,400ms gap — no events processed ★

Phase 3: Everything unblocks at once
  +17,596ms  Background.StyledWindow created
  +17,751ms  ddcutil done, asdbctl done, brightnessctl done
  +17,759ms  cliphist check done
  +17,824ms  nmcli getWifiStatus/getNetworks/getEthernetInterfaces done
  +18,140ms  nmcli loadSavedConnections done
  +18,226ms  ipinfo.io response received
  +19,755ms  open-meteo weather response received
```

## System Information

- **GPU:** AMD Radeon 860M (RDNA 4, krackan1) + NVIDIA RTX 5070 Max-Q (discrete, unused for rendering)
- **Mesa:** 26.0.3-arch1.1
- **Mesa shader cache:** 67MB in `~/.cache/mesa_shader_cache/`
- **Qt pipeline cache:** 148KB in `~/.cache/quickshell/qtpipelinecache-*/qqpc_opengl`
- **QML cache:** `~/.cache/quickshell/qmlcache/`
- **Font:** Material Symbols Rounded — **14MB** variable font (4 axes: FILL, GRAD, opsz, wght)
- **Screen:** eDP-1, 165Hz
- **Render loop:** Threaded (`QSG_RENDER_LOOP=threaded`)
- **OpenGL contexts at startup:** 9 (one per window)
