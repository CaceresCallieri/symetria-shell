# Qt / QuickShell Startup Profiling Tools Reference

Complete reference for extracting diagnostic output from Qt's QML engine and QuickShell during startup. All commands tested and verified on Qt 6.10.2 / QuickShell r125 / Arch Linux.

**Convention:** All examples use `qs -c symmetria` as the target. For a disposable test config, replace with `qs -p /path/to/test`.

---

## 1. QuickShell Built-in Verbosity Flags

### `-v` (INFO level)

Shows QuickShell internal INFO messages: crash handler init, Wayland hooks, IPC server, tooling support.

```bash
qs -v -c symmetria
```

Output includes:
```
INFO quickshell.crashhandler: Crash handler initialized.
INFO quickshell.logging: Saving detailed logs to "/run/user/1000/quickshell/by-id/<id>/log.log"
INFO quickshell.wayland.safederef: Installed wl_proxy_get_listener hook.
INFO quickshell.ipc: Started IPC server on path "/run/user/1000/quickshell/by-id/<id>/ipc.sock"
INFO quickshell.tooling: Not enabling QML tooling support, qmlls.ini is missing
```

### `-vv` (DEBUG level)

Shows everything from `-v` plus the QML scanner, URL interceptor, path initialization, and logging subsystem internals. **This is the most useful built-in flag for startup debugging.**

```bash
qs -vv -c symmetria
```

Additional output:
```
DEBUG quickshell.qmlscanner: Scanning qml file "/path/to/shell.qml"
DEBUG quickshell.qmlscanner: Scanning directory "/path/to/config"
DEBUG quickshell.qmlscanner: Synthesized qmldir for "/path/to/config" ...
DEBUG quickshell.interceptor: Got intercept for "shell.qml" contains ""
DEBUG quickshell.interceptor: Passing through intercept QUrl("qs:@/qs/shell.qml") to QUrl("file:///path/to/shell.qml")
DEBUG quickshell.interceptor: Blackholed import URL QUrl("qs:@/QtQuick/qmldir")
DEBUG quickshell.paths: Initialized instance runtime path: "/run/user/1000/quickshell/by-id/<id>"
```

### `--log-rules`

Passes rules in `QT_LOGGING_RULES` format directly to QuickShell:

```bash
qs --log-rules "quickshell.*=true;qt.qml.import=true" -c symmetria
```

Equivalent to setting the env var, but scoped to this instance.

### `--log-times`

Adds timestamps to every log line:

```bash
qs --log-times -vv -c symmetria
```

### `--debug <port>` / `--waitfordebug`

Opens a QML debugger port. See Section 4 (QML Profiler).

```bash
qs --debug 3768 --waitfordebug -c symmetria
```

---

## 2. Qt QML Logging Categories

Enable via `QT_LOGGING_RULES` env var or `--log-rules` flag. All categories are from `libQt6Qml.so` and `libQt6Quick.so` (Qt 6.10.2).

### QML Engine Categories (`qt.qml.*`)

| Category | What it logs | Startup relevance |
|----------|-------------|-------------------|
| `qt.qml.import` | **Every import resolution step**: addImportPath, addLibraryImport, resolvePlugin, resolveType, locateLocalQmldir | **HIGH** — shows the full import cascade |
| `qt.qml.qmlcomponent` | QQmlComponent lifecycle events | MEDIUM — tracks component creation |
| `qt.qml.diskcache` | Disk cache hits/misses, save errors | MEDIUM — reveals compilation overhead |
| `qt.qml.typecompiler` | QML type compilation | MEDIUM — shows what's being compiled |
| `qt.qml.typeresolution.cycle` | Circular type resolution detection | LOW — only fires on errors |
| `qt.qml.typeregistration` | Type registration events | LOW |
| `qt.qml.context` | QML context creation/destruction | LOW |
| `qt.qml.binding.removal` | Binding teardown | LOW |
| `qt.qml.propertybinding` | Property binding setup | LOW — fires per-binding, very verbose |
| `qt.qml.signalhandler` | Signal handler connections | LOW |
| `qt.qml.object.connect` | QObject::connect calls | LOW |
| `qt.qml.defaultmethod` | Default method resolution | LOW |
| `qt.qml.overloadresolution` | Method overload resolution | LOW |
| `qt.qml.injectedparameter` | Injected parameter resolution | LOW |
| `qt.qml.invalidOverride` | Invalid property overrides | LOW — check for warnings |
| `qt.qml.rootObjectProperties` | Root object property setup | LOW |
| `qt.qml.js.globals` | JavaScript global object setup | LOW |
| `qt.qml.usedbeforedeclared` | Used-before-declared warnings | LOW |
| `qt.qml.coercingTypeAssertion` | Type coercion warnings | LOW |
| `qt.qml.list.incompatible` | Incompatible list type warnings | LOW |
| `qt.qml.listvalueconversion` | List value conversion | LOW |
| `qt.qml.method.behavior` | Method behavior changes | LOW |
| `qt.qml.states` | State transitions | LOW |
| `qt.qml.v4.asm` | V4 JIT assembly output | NICHE |

### GC Categories (`qt.qml.gc.*`)

| Category | What it logs |
|----------|-------------|
| `qt.qml.gc.statistics` | GC run statistics (heap size, collected bytes) |
| `qt.qml.gc.stateTransitions` | GC state machine transitions |
| `qt.qml.gc.stepExecution` | Individual GC step timing |
| `qt.qml.gc.forcedRuns` | When GC is forced (memory pressure) |
| `qt.qml.gc.allocatorStats` | Memory allocator statistics |

### Qt Quick Categories (`qt.quick.*`)

| Category | What it logs | Startup relevance |
|----------|-------------|-------------------|
| `qt.quick.focus` | Focus chain changes | LOW |
| `qt.quick.itemview.lifecycle` | ListView/GridView delegate lifecycle | **MEDIUM** — tracks delegate creation |
| `qt.quick.itemview.count` | Item count changes in views | LOW |
| `qt.quick.dirty` | Dirty node tracking in scene graph | LOW |
| `qt.quick.window` | Window lifecycle events | MEDIUM |
| `qt.quick.image` | Image loading | LOW |
| `qt.quick.hover.trace` | Hover event tracing | LOW |

### Scene Graph Categories (`qt.scenegraph.*`)

| Category | What it logs | Startup relevance |
|----------|-------------|-------------------|
| `qt.scenegraph.general` | Render loop type, animation driver, RHI backend, context creation | **HIGH** — shows OpenGL/Vulkan init |
| `qt.scenegraph.renderloop` | Render loop state changes | MEDIUM |
| `qt.scenegraph.time.renderloop` | **Frame timing**: polish, lock, sync, render, swap (ms) | **HIGH** — identifies render stalls |
| `qt.scenegraph.time.renderer` | Renderer timing: preprocess, updates, rendering | **HIGH** |
| `qt.scenegraph.time.texture` | Texture upload timing | LOW |
| `qt.scenegraph.time.glyph` | Glyph cache timing | LOW |
| `qt.scenegraph.time.compilation` | Shader compilation timing | MEDIUM |
| `qt.scenegraph.text` | Text rendering | LOW |
| `qt.scenegraph.leaks` | Resource leak detection | LOW |

### Qt Quick Controls Categories (`qt.quick.controls.*`)

| Category | What it logs |
|----------|-------------|
| `qt.quick.controls.style` | Style loading |
| `qt.quick.controls.styleplugin` | Style plugin loading |
| `qt.quick.controls.popup` | Popup lifecycle |
| `qt.quick.controls.pane` | Pane layout |
| `qt.quick.layouts` | Layout calculations |

### Command: Import tracing (most useful for startup)

```bash
QT_LOGGING_RULES="qt.qml.import=true" qs -c symmetria 2>&1 | tee /tmp/qs-import-trace.log
```

Sample output:
```
DEBUG qt.qml.import: addImportPath: "/usr/lib/qt6/qml"
DEBUG qt.qml.import: addLibraryImport: shell.qml "QtQuick" version "(latest)" as ""
DEBUG qt.qml.import: importExtension: shell.qml loaded ":/qt-project.org/imports/QtQuick/qmldir"
DEBUG qt.qml.import: resolveType: shell.qml "Item"  =>  "QQuickItem"  TYPE
```

### Command: Full QML + scenegraph timing

```bash
QT_LOGGING_RULES="qt.qml.import=true;qt.qml.diskcache=true;qt.qml.qmlcomponent=true;qt.qml.typecompiler=true;qt.scenegraph.time.*=true;qt.scenegraph.general=true" \
  qs --log-times -c symmetria 2>&1 | tee /tmp/qs-full-trace.log
```

### Command: Everything (VERY verbose — use for short tests only)

```bash
QT_LOGGING_RULES="qt.qml.*=true;qt.quick.*=true;qt.scenegraph.*=true" \
  qs --log-times -vv -c symmetria 2>&1 | tee /tmp/qs-everything.log
```

---

## 3. QML Environment Variables

### Import Tracing

**`QML_IMPORT_TRACE=1`** — Enables `qt.qml.import` debug output. Equivalent to `QT_LOGGING_RULES="qt.qml.import=true"` but via env var.

```bash
QML_IMPORT_TRACE=1 qs -c symmetria 2>&1 | tee /tmp/qs-import-trace.log
```

Output shows every import resolution step: library imports, file imports, plugin loading, type resolution. See Section 2 for sample output.

### Disk Cache Control

**`QML_DISK_CACHE_PATH=<path>`** — Redirect the QML bytecode cache to a custom directory:

```bash
QML_DISK_CACHE_PATH=/tmp/qml-cache-debug qs -c symmetria
ls -laR /tmp/qml-cache-debug  # Inspect cached files
```

**`QML_DISABLE_DISK_CACHE=1`** — Force recompilation of all QML files (no cache read or write). Useful for timing the compilation overhead:

```bash
QML_DISABLE_DISK_CACHE=1 qs -c symmetria  # Cold compilation every time
```

**`QML_FORCE_DISK_CACHE=1`** — Only load from cache, fail if a file has no cached version. Useful to confirm everything is cached:

```bash
QML_FORCE_DISK_CACHE=1 qs -c symmetria  # Will error on uncached files
```

**`QML_DISK_CACHE=<options>`** — Fine-grained cache control. Accepts comma-separated options. Mainly used to set the cache path without a separate env var.

### Compilation and Unit Statistics

**`QML_SHOW_UNIT_STATS=1`** — Prints size statistics for every compiled QML unit:

```bash
QML_SHOW_UNIT_STATS=1 qs -c symmetria 2>&1 | grep "Generated" | head -20
```

Output:
```
DEBUG: Generated JS unit that is 640 bytes contains:
DEBUG:      80 bytes for non-code function data for 1 functions
DEBUG:      0 bytes for 0 translations
DEBUG: Generated QML unit that is 268 bytes big contains:
DEBUG:      1 functions
DEBUG:      908 for JS unit
DEBUG:      20 for imports
DEBUG:      224 for 2 objects
DEBUG:      2 bindings
DEBUG:      16 bytes total byte code
DEBUG:      10 strings
DEBUG:      264 bytes total strings
```

**Startup relevance:** Shows how many objects and bindings each file contributes. Large unit sizes = more work for `beginCreate()`.

### Type Checking

**`QML_CHECK_TYPES=1`** — Enables runtime type checking. May produce warnings for type mismatches.

**`QML_DUMP_ERRORS=1`** — Dumps detailed error information.

### Animation Diagnostics

**`QML_ANIMATION_TICK_DUMP=1`** — Dumps animation tick information. Useful if animations are suspected of causing stalls.

### Deferred Properties

**`QML_DISABLE_INTERNAL_DEFERRED_PROPERTIES=1`** — Disables Qt's internal deferred property loading (separate from QuickShell's incubator). May change startup behavior.

---

## 4. QML Profiler (qmlprofiler)

Qt ships a command-line QML profiler at `/usr/lib/qt6/bin/qmlprofiler`. This captures detailed timing for: JavaScript execution, memory allocation, pixmap cache, scene graph operations, animations, painting, **compiling**, **creating (object instantiation)**, **binding evaluation**, signal handling, and input events.

### Step 1: Launch QuickShell with debug port

```bash
qs --debug 3768 -c symmetria
```

Output: `QML Debugger: Waiting for connection on port 3768...`

For blocking startup profiling (capture from the very first instruction):

```bash
qs --debug 3768 --waitfordebug -c symmetria
```

This pauses execution until a debugger connects. The app will NOT start rendering until the profiler attaches.

### Step 2: Attach the profiler

In another terminal:

```bash
/usr/lib/qt6/bin/qmlprofiler -a localhost -p 3768 -o /tmp/symmetria-profile.qtd
```

The `.qtd` file can be opened in Qt Creator for timeline visualization.

### Step 2b: Interactive mode

```bash
/usr/lib/qt6/bin/qmlprofiler -a localhost -p 3768 -o /tmp/symmetria-profile.qtd --interactive
```

Commands: `r` (toggle recording), `o [file]` (output), `c` (clear), `f [file]` (flush), `q` (quit).

### Step 3: Feature filtering

To capture only creation + binding + compiling (the startup-relevant features):

```bash
/usr/lib/qt6/bin/qmlprofiler -a localhost -p 3768 \
  --include creating,binding,compiling,javascript \
  -o /tmp/symmetria-startup-profile.qtd
```

All available features: `javascript`, `memory`, `pixmapcache`, `scenegraph`, `animations`, `painting`, `compiling`, `creating`, `binding`, `handlingsignal`, `inputevents`, `debugmessages`.

### Step 4: View in Qt Creator

```bash
paru -S qt6-creator  # if not installed
qtcreator /tmp/symmetria-profile.qtd
```

The Timeline view shows a waterfall of all operations. Look for:
- **Creating** bars — object instantiation (`beginCreate()` / `completeCreate()`)
- **Compiling** bars — QML → bytecode compilation
- **Binding** bars — property binding evaluation

### Caveats

- The debug port adds **significant overhead** (2-5x slower). Timing values are relative, not absolute.
- `--waitfordebug` is required to capture the very start of execution.
- QuickShell's custom URL interceptor (`qs:@/`) may confuse the profiler's file resolution.

---

## 5. QV4 (JavaScript Engine) Environment Variables

### Bytecode and JIT Inspection

**`QV4_SHOW_BYTECODE=1`** — Dumps V4 bytecode for every compiled JavaScript function:

```bash
QV4_SHOW_BYTECODE=1 qs -c symmetria 2>&1 | tee /tmp/qs-bytecode.log
```

Output per function:
```
=== Bytecode for "expression for onCompleted" strict mode false register count 10
       1       0: ca                       CreateCallContext
              1: 2e 00                    LoadQmlContextPropertyLookup 0
              3: 18 07                    StoreReg r1
              ...
```

**Startup relevance:** Shows every JS function being compiled. Massive output for a full shell — redirect to file.

**`QV4_SHOW_ASM=1`** — Dumps JIT-compiled native assembly. Requires JIT to be active (not interpreter mode):

```bash
QV4_SHOW_ASM=1 qs -c symmetria 2>&1 | tee /tmp/qs-asm.log
```

**`QV4_SHOW_ESCAPING_VARS=1`** — Shows variables that escape their scope (forced to heap allocation).

### JIT / Interpreter Control

**`QV4_FORCE_INTERPRETER=1`** — Disables JIT compilation, forces pure interpreter mode. Slower execution but eliminates JIT compilation overhead:

```bash
QV4_FORCE_INTERPRETER=1 qs -c symmetria  # Compare with normal to measure JIT cost
```

**`QV4_JIT_CALL_THRESHOLD=<n>`** — Number of function calls before JIT kicks in (default varies by platform). Setting high effectively disables JIT for startup:

```bash
QV4_JIT_CALL_THRESHOLD=999999 qs -c symmetria  # Delay JIT until after startup
```

### Perf Map for Linux `perf`

**`QV4_PROFILE_WRITE_PERF_MAP=1`** — Writes a `/tmp/perf-<pid>.map` file mapping JIT-compiled code addresses to function names. This allows `perf` to resolve V4 JIT frames:

```bash
QV4_PROFILE_WRITE_PERF_MAP=1 perf record -g qs -c symmetria
perf report  # V4 functions now have names instead of [unknown]
```

**Note:** Only writes a map if JIT is active and functions get JIT-compiled. On a short-lived test app it may not trigger.

### GC Tuning

**`QV4_GC_TIMELIMIT=<ms>`** — Maximum time per GC slice (default: 4ms). Increasing may reduce GC frequency during startup:

```bash
QV4_GC_TIMELIMIT=20 qs -c symmetria  # Allow longer GC slices
```

**`QV4_GC_MAX_STACK_SIZE=<bytes>`** — Maximum GC mark stack size.

**`QV4_MM_AGGRESSIVE_GC=1`** — Forces GC after every allocation. Extremely slow but catches memory issues:

```bash
QV4_MM_AGGRESSIVE_GC=1 qs -c symmetria  # Warning: VERY slow
```

### Stack Limits

**`QV4_JS_MAX_STACK_SIZE=<bytes>`** — JavaScript stack size limit.
**`QV4_MAX_CALL_DEPTH=<n>`** — Maximum call recursion depth.
**`QV4_STACK_SOFT_LIMIT=<bytes>`** — Soft stack limit before warning.
**`QV4_CRASH_ON_STACKOVERFLOW=1`** — Crash instead of throwing on stack overflow.

---

## 6. Scene Graph (QSG) Environment Variables

### Information and Timing

**`QSG_INFO=1`** — Prints scene graph initialization info: render loop type, RHI backend, GPU info, pipeline cache:

```bash
QSG_INFO=1 qs -c symmetria 2>&1 | head -30
```

Output:
```
DEBUG qt.scenegraph.general: threaded render loop
DEBUG qt.scenegraph.general: Using sg animation driver
DEBUG qt.scenegraph.general: Animation Driver: using vsync: 6.06 ms
DEBUG qt.scenegraph.general: Creating QRhi with backend OpenGL for window 0x...
DEBUG qt.rhi.general: OpenGL VENDOR: AMD RENDERER: AMD Radeon 860M Graphics ...
DEBUG qt.scenegraph.general: Seeded pipeline cache from 'qqpc_opengl'
DEBUG qt.scenegraph.general: rhi texture atlas dimensions: 1024x1024
```

**`QSG_RENDER_TIMING=1`** — Enables `qt.scenegraph.time.*` logging. Shows per-frame timing:

```bash
QSG_RENDER_TIMING=1 qs -c symmetria 2>&1 | grep "time in renderer\|polishAndSync\|syncAndRender"
```

Output:
```
DEBUG qt.scenegraph.time.renderloop: [window 0x...][gui thread] polishAndSync: start, elapsed since last call: 11 ms
DEBUG qt.scenegraph.time.renderloop: [window 0x...][render thread] syncAndRender: frame rendered in 0ms, sync=0, render=0, swap=0
DEBUG qt.scenegraph.time.renderloop: [window 0x...][gui thread] Frame prepared, polish=0 ms, lock=0 ms, blockedForSync=4 ms, animations=0 ms
DEBUG qt.scenegraph.time.renderer: time in renderer: total=0ms, preprocess=0, updates=0, rendering=0
```

**Startup relevance:** During the freeze, no frames are rendered. The ABSENCE of `polishAndSync` messages during the freeze period confirms the GUI thread is blocked in QML compilation, not rendering.

### Render Loop Control

**`QSG_RENDER_LOOP=<type>`** — Force a specific render loop. Options: `basic` (single-threaded), `threaded` (default), `windows`:

```bash
QSG_RENDER_LOOP=basic qs -c symmetria  # Single-threaded rendering (for debugging)
```

### Visualization

**`QSG_VISUALIZE=<mode>`** — Overlay debug visualization. Modes: `batches`, `clip`, `changes`, `overdraw`:

```bash
QSG_VISUALIZE=batches qs -c symmetria   # Shows batching
QSG_VISUALIZE=overdraw qs -c symmetria  # Shows overdraw
QSG_VISUALIZE=changes qs -c symmetria   # Shows dirty regions
```

### RHI / GPU Debugging

**`QSG_RHI_PROFILE=1`** — RHI resource profiling.
**`QSG_RHI_DEBUG_LAYER=1`** — Enable GPU validation layer (Vulkan/D3D12).
**`QSG_RHI_BACKEND=<backend>`** — Force RHI backend: `opengl`, `vulkan`, `metal`, `d3d11`, `d3d12`.

```bash
QSG_RHI_PROFILE=1 QSG_INFO=1 qs -c symmetria 2>&1 | tee /tmp/qs-rhi.log
```

### Other QSG Variables

| Variable | Purpose |
|----------|---------|
| `QSG_NO_VSYNC=1` | Disable vsync (uncapped framerate) |
| `QSG_FIXED_ANIMATION_STEP=1` | Fixed animation timestep |
| `QSG_RHI_PREFER_SOFTWARE_RENDERER=1` | Force software rendering |
| `QSG_RHI_DISABLE_DISK_CACHE=1` | Disable pipeline cache |
| `QSG_RENDERER_DEBUG=<options>` | Renderer debug output |
| `QSG_OPENGL_DEBUG=1` | OpenGL debug output |

---

## 7. QuickShell Logging Categories

All categories extracted from the `quickshell` binary (r125). Enable via `QT_LOGGING_RULES` or `--log-rules`.

### Core Categories

| Category | What it logs |
|----------|-------------|
| `quickshell.bare` | Bare QuickShell core lifecycle |
| `quickshell.crashhandler` | Crash handler init, memfd creation |
| `quickshell.crashreporter` | Crash report generation |
| `quickshell.colorquantizer` | Color quantizer (wallpaper colors) |
| `quickshell.desktopentry` | .desktop file parsing |
| `quickshell.incubator` | **QML incubator lifecycle** — object creation scheduling |
| `quickshell.interceptor` | **URL interceptor** — shows every file load |
| `quickshell.ipc` | IPC server start/connections |
| `quickshell.ipchandler` | IPC message handling |
| `quickshell.linter` | QML linting |
| `quickshell.logging` | Logging subsystem init |
| `quickshell.paths` | Path initialization (runtime, vfs, symlinks) |
| `quickshell.qmlscanner` | **QML directory scanning** — shows qmldir synthesis |
| `quickshell.tooling` | QML tooling (qmlls) support |

### Networking / Bluetooth

| Category | What it logs |
|----------|-------------|
| `quickshell.bluetooth` | Bluetooth manager |
| `quickshell.bluetooth.adapter` | BT adapter events |
| `quickshell.bluetooth.device` | BT device events |
| `quickshell.network` | Network manager core |
| `quickshell.network.device` | Network device events |
| `quickshell.network.networkmanager` | NetworkManager integration |
| `quickshell.network.nm_settings` | NM settings |
| `quickshell.wifinetwork` | WiFi network details |

### D-Bus

| Category | What it logs |
|----------|-------------|
| `quickshell.dbus` | D-Bus core |
| `quickshell.dbus.dbusmenu` | D-Bus menu protocol |
| `quickshell.dbus.objectmanager` | D-Bus object manager |
| `quickshell.dbus.properties` | D-Bus property changes |

### Services

| Category | What it logs |
|----------|-------------|
| `quickshell.service.greetd` | Greetd (login manager) |
| `quickshell.service.mp.player` | MPRIS player |
| `quickshell.service.mpris.watcher` | MPRIS watcher |
| `quickshell.service.notifications` | Notification daemon |
| `quickshell.service.pam` | PAM authentication |
| `quickshell.service.pipewire.*` | PipeWire (connection, defaults, device, link, loop, metadata, node, peak, registry) |
| `quickshell.service.polkit` | Polkit agent |
| `quickshell.service.polkit.listener` | Polkit listener |
| `quickshell.service.polkit.state` | Polkit state |
| `quickshell.service.powerprofiles` | Power profiles |
| `quickshell.service.sni.host` | System tray host |
| `quickshell.service.sni.item` | System tray items |
| `quickshell.service.sni.watcher` | System tray watcher |
| `quickshell.service.upower` | UPower |
| `quickshell.service.upower.device` | UPower devices |

### I/O and Wayland

| Category | What it logs |
|----------|-------------|
| `quickshell.io.fileview` | File view operations |
| `quickshell.io.socket` | Socket I/O |
| `quickshell.wayland.buffer` | Wayland buffer management |
| `quickshell.wayland.buffer.dmabuf` | DMA-BUF operations |
| `quickshell.wayland.buffer.shm` | Shared memory buffers |
| `quickshell.wayland.idle_inhibit` | Idle inhibitor |
| `quickshell.wayland.idle_notify` | Idle notification |
| `quickshell.wayland.safederef` | Safe Wayland dereference hook |
| `quickshell.wayland.screencopy.*` | Screen capture (hyprland, icc, wlr) |
| `quickshell.wayland.shortcuts_inhibit` | Shortcuts inhibitor |
| `quickshell.wayland.toplevelManagement` | Toplevel management |

### Window Manager

| Category | What it logs |
|----------|-------------|
| `quickshell.hyprland.ipc` | Hyprland IPC |
| `quickshell.hyprland.ipc.events` | Hyprland IPC events |
| `quickshell.I3.ipc` | i3/Sway IPC |
| `quickshell.I3.ipc.events` | i3/Sway events |
| `quickshell.wm.workspace` | Workspace management |
| `quickshell.wm.wayland.workspace` | Wayland workspace protocol |

### Command: Most useful for startup

```bash
qs --log-rules "quickshell.incubator=true;quickshell.qmlscanner=true;quickshell.interceptor=true" \
  --log-times -vv -c symmetria 2>&1 | tee /tmp/qs-startup-debug.log
```

---

## 8. Linux `perf` Profiling

### Basic CPU Profile

```bash
perf record -g -o /tmp/qs-perf.data -- qs -c symmetria
# Wait for startup to complete, then Ctrl+C
perf report -i /tmp/qs-perf.data --stdio --no-children
```

### With V4 JIT Symbol Resolution

```bash
QV4_PROFILE_WRITE_PERF_MAP=1 perf record -g -o /tmp/qs-perf.data -- qs -c symmetria
# After exit, the perf map enables JIT function name resolution:
perf report -i /tmp/qs-perf.data
```

### Timed Profile (capture first 30 seconds only)

```bash
perf record -g -o /tmp/qs-perf.data -- timeout 30 qs -c symmetria
perf report -i /tmp/qs-perf.data --stdio --no-children | head -60
```

### Flamegraph Visualization

```bash
# Install flamegraph tools
paru -S flamegraph

# Generate flamegraph
perf record -g -o /tmp/qs-perf.data -- qs -c symmetria
perf script -i /tmp/qs-perf.data | stackcollapse-perf.pl | flamegraph.pl > /tmp/qs-flamegraph.svg
firefox /tmp/qs-flamegraph.svg
```

Or use Hotspot (GUI):
```bash
paru -S hotspot
hotspot /tmp/qs-perf.data
```

### Focus on Specific Functions

```bash
# Profile only QQmlComponent functions
perf record -g -o /tmp/qs-perf.data -- qs -c symmetria
perf report -i /tmp/qs-perf.data --stdio --symbol-filter='QQmlComponent\|beginCreate\|completeCreate'
```

### Perf stat (high-level counters)

```bash
perf stat -d -- timeout 30 qs -c symmetria
```

Output: instruction count, cache misses, branch misses, IPC — useful for comparing Qt versions.

---

## 9. `strace` System Call Tracing

### System Call Summary

```bash
strace -c -f qs -c symmetria 2>&1 | tail -40
```

Shows a table of all system calls with count, time, and errors. Key finding: during the freeze, the main thread is in a `ppoll` loop with ~90ms timeout — the event loop IS running but no events arrive.

### File Access Tracing

```bash
strace -f -e trace=openat -o /tmp/qs-files.txt qs -c symmetria
# After startup:
grep '\.qml\|qmldir\|\.so' /tmp/qs-files.txt | wc -l   # Count QML file opens
grep 'ENOENT' /tmp/qs-files.txt | wc -l                   # Count failed lookups
```

**Startup relevance:** Shows every file the QML engine tries to open, including failed lookups (import search paths). Excessive ENOENT = wasted I/O from import resolution.

### Timing Individual Calls

```bash
strace -T -f -e trace=poll,ppoll,futex -o /tmp/qs-strace.log qs -c symmetria
```

The `-T` flag shows time spent in each call. Look for:
- `ppoll(..., {tv_sec=0, tv_nsec=90000000})` — main thread polling with 90ms timeout
- `futex(FUTEX_WAIT)` — render threads blocked waiting for work

### Timestamp Mode

```bash
strace -t -f -e trace=openat,mmap -o /tmp/qs-strace-timed.log qs -c symmetria
```

The `-t` flag adds wall-clock timestamps, allowing correlation with log output.

---

## 10. QML `console.time()` / `console.timeEnd()` Instrumentation

QML supports `console.time(label)` and `console.timeEnd(label)` for manual timing:

```qml
Component.onCompleted: {
    console.time("myComponent-init")
    // ... initialization code ...
    console.timeEnd("myComponent-init")
}
```

Output: `myComponent-init: 42ms`

### Heartbeat Profiler (proven technique)

Add to `shell.qml` inside ShellRoot:

```qml
Component.onCompleted: console.log("[BOOT] ShellRoot @ " + Date.now())
Timer {
    interval: 500; running: true; repeat: true; property int b: 0
    onTriggered: {
        b++;
        console.log("[BOOT:HB] #" + b + " @ " + Date.now());
        if (b >= 10) running = false;
    }
}
```

**Interpretation:**
- Beat #1 at ~+500ms = event loop responsive (no freeze)
- Beat #1 at ~+20000ms = event loop frozen for 20 seconds

### Per-Module Timing

Add `Component.onCompleted: console.log("[BOOT] <Name> @ " + Date.now())` to each top-level component. Sort by timestamp to build a startup waterfall.

### `console.profile()` / `console.profileEnd()` (Requires Debugger)

When connected to a QML debugger (via `--debug`), these start/stop the built-in profiler:

```qml
Component.onCompleted: {
    console.profile("startup")
    // ... code ...
    console.profileEnd("startup")
}
```

Without a debugger, these log: `Ignoring console.profileEnd(): the debug service is disabled.`

---

## 11. Composite Diagnostic Commands

### A. Import resolution + timing (RECOMMENDED FIRST STEP)

```bash
QML_IMPORT_TRACE=1 qs --log-times -v -c symmetria 2>&1 | tee /tmp/qs-import-timing.log
```

### B. Full engine diagnostics

```bash
QT_LOGGING_RULES="qt.qml.import=true;qt.qml.diskcache=true;qt.qml.qmlcomponent=true;qt.qml.typecompiler=true;qt.scenegraph.time.*=true;qt.scenegraph.general=true;quickshell.incubator=true;quickshell.qmlscanner=true;quickshell.interceptor=true" \
QSG_RENDER_TIMING=1 \
QML_SHOW_UNIT_STATS=1 \
  qs --log-times -vv -c symmetria 2>&1 | tee /tmp/qs-full-diagnostics.log
```

### C. CPU profiling with symbol resolution

```bash
QV4_PROFILE_WRITE_PERF_MAP=1 \
  perf record -g -o /tmp/qs-perf.data -- qs -c symmetria
# After Ctrl+C:
perf report -i /tmp/qs-perf.data --stdio --no-children 2>&1 | head -80
```

### D. System call analysis

```bash
strace -c -f -o /tmp/qs-strace-summary.txt qs -c symmetria
# After Ctrl+C, view:
cat /tmp/qs-strace-summary.txt
```

### E. QML Profiler capture for Qt Creator

```bash
# Terminal 1:
qs --debug 3768 --waitfordebug -c symmetria

# Terminal 2:
/usr/lib/qt6/bin/qmlprofiler -a localhost -p 3768 \
  --include creating,binding,compiling,javascript \
  -o /tmp/symmetria-startup.qtd
```

### F. Compare interpreter vs JIT

```bash
echo "=== Normal (JIT) ===" && time qs -c symmetria &
sleep 30 && kill %1

echo "=== Interpreter only ===" && time QV4_FORCE_INTERPRETER=1 qs -c symmetria &
sleep 30 && kill %1
```

### G. Compare disk cache on vs off

```bash
echo "=== With cache ===" && rm -rf ~/.cache/quickshell/qmlcache
time qs -c symmetria &
sleep 30 && kill %1

echo "=== Without cache ===" && rm -rf ~/.cache/quickshell/qmlcache
time QML_DISABLE_DISK_CACHE=1 qs -c symmetria &
sleep 30 && kill %1
```

---

## 12. Summary: What to Use When

| Question | Tool |
|----------|------|
| "WHERE is time spent in C++ code?" | `perf record -g` + flamegraph |
| "WHICH QML files are being loaded?" | `QML_IMPORT_TRACE=1` or `qt.qml.import` |
| "HOW MANY objects/bindings per file?" | `QML_SHOW_UNIT_STATS=1` |
| "IS the event loop frozen?" | Heartbeat Timer profiler |
| "WHAT system calls happen during freeze?" | `strace -T -f -e ppoll,futex` |
| "IS it GC pressure?" | `qt.qml.gc.*=true` logging |
| "IS it JIT compilation?" | Compare `QV4_FORCE_INTERPRETER=1` vs normal |
| "IS it disk cache?" | Compare `QML_DISABLE_DISK_CACHE=1` vs normal |
| "IS it GPU/rendering?" | `QSG_INFO=1` + `QSG_RENDER_TIMING=1` |
| "WHICH component takes longest to create?" | `qs --debug 3768` + `qmlprofiler --include creating` |
| "IS it import resolution?" | `QML_IMPORT_TRACE=1` + strace openat |
| "WHAT does QuickShell do before QML loads?" | `qs -vv --log-times` |
| "IS it the bytecode compilation step?" | `QV4_SHOW_BYTECODE=1` (shows what gets compiled) |

---

## 13. Environment Variables Quick Reference

### QML Engine

| Variable | Purpose |
|----------|---------|
| `QML_IMPORT_TRACE=1` | Trace all import resolution |
| `QML_SHOW_UNIT_STATS=1` | Print compiled unit sizes |
| `QML_DISABLE_DISK_CACHE=1` | Force recompilation |
| `QML_FORCE_DISK_CACHE=1` | Only load from cache |
| `QML_DISK_CACHE_PATH=<path>` | Custom cache directory |
| `QML_CHECK_TYPES=1` | Runtime type checking |
| `QML_DUMP_ERRORS=1` | Detailed error output |
| `QML_ANIMATION_TICK_DUMP=1` | Animation tick info |
| `QML_DISABLE_INTERNAL_DEFERRED_PROPERTIES=1` | Disable deferred properties |
| `QML_IMPORT_PATH=<path>` | Additional import paths |
| `QML_PLUGIN_PATH=<path>` | Additional plugin paths |

### V4 JavaScript Engine

| Variable | Purpose |
|----------|---------|
| `QV4_FORCE_INTERPRETER=1` | Disable JIT |
| `QV4_JIT_CALL_THRESHOLD=<n>` | JIT activation threshold |
| `QV4_SHOW_BYTECODE=1` | Dump bytecode |
| `QV4_SHOW_ASM=1` | Dump JIT assembly |
| `QV4_SHOW_ESCAPING_VARS=1` | Show escaping variables |
| `QV4_PROFILE_WRITE_PERF_MAP=1` | Write perf map for symbol resolution |
| `QV4_GC_TIMELIMIT=<ms>` | GC time limit per slice |
| `QV4_GC_MAX_STACK_SIZE=<bytes>` | GC stack limit |
| `QV4_MM_AGGRESSIVE_GC=1` | GC after every allocation |
| `QV4_JS_MAX_STACK_SIZE=<bytes>` | JS stack limit |
| `QV4_MAX_CALL_DEPTH=<n>` | Max recursion depth |

### Scene Graph

| Variable | Purpose |
|----------|---------|
| `QSG_INFO=1` | Scene graph init info |
| `QSG_RENDER_TIMING=1` | Per-frame timing |
| `QSG_RENDER_LOOP=basic\|threaded` | Force render loop type |
| `QSG_VISUALIZE=batches\|overdraw\|clip\|changes` | Debug visualization |
| `QSG_NO_VSYNC=1` | Disable vsync |
| `QSG_RHI_PROFILE=1` | RHI resource profiling |
| `QSG_RHI_DEBUG_LAYER=1` | GPU validation |
| `QSG_RHI_BACKEND=opengl\|vulkan` | Force RHI backend |
| `QSG_RENDERER_DEBUG=<opts>` | Renderer debug info |

### Qt Core

| Variable | Purpose |
|----------|---------|
| `QT_LOGGING_RULES=<rules>` | Logging rules (`;`-separated) |
| `QT_LOGGING_CONF=<file>` | Logging config file |
| `QT_LOGGING_DEBUG=1` | Debug the logging system itself |
| `QT_LOGGING_TO_CONSOLE=1` | Force console output |

---

## 14. Non-Existent Variables (Confirmed Absent)

The following variables are sometimes referenced online but do **NOT exist** in Qt 6.10.2:

- `QML_COMPILER_DUMP` — does not exist
- `QML_DISABLE_OPTIMIZER` — does not exist
- `QT_SLOW_EVENTS_REPORTING` — does not exist in any Qt 6 library
- `QML_COMPILER_STATS` — does not exist (use `QML_SHOW_UNIT_STATS` instead)
