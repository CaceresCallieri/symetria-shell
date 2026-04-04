# Root Cause Bisection — O(n²) Notification Deserialization

**Date:** 2026-04-04 (evening session, post-reboot), updated 2026-04-04 (night session)
**System:** Arch Linux, kernel 6.19.10-zen1-1-zen, Qt 6.10.2, Quickshell r125 (854088c)
**Branch:** `fix/deferred-panels-v2` (from `main`)

---

## ROOT CAUSE IDENTIFIED (CORRECTED)

**The 23-second startup freeze is caused by O(n²) notification deserialization in
`services/Notifs.qml`.** With 6,890 accumulated notifications in `~/.local/state/symmetria/notifs.json`
(2.2MB), the `onLoaded` handler creates QML objects in a loop using `root.list.push()`, triggering
a binding cascade on every push.

### Why the bisection pointed to the rebrand commit

The git bisection correctly identified commit `0fbdbed` ("rebrand Caelestia to Symmetria") as
the boundary. But the real reason is that this commit changed `Paths.state` from
`~/.local/state/caelestia` to `~/.local/state/symmetria`. The caelestia state path doesn't exist
(broken symlink), so pre-rebrand commits load zero notifications. Post-rebrand commits find the
real `notifs.json` with 6,890 entries.

**The C++ plugin hypothesis was WRONG.** Both plugins are functionally identical. The original
analysis failed to account for the state file path change hidden inside the rebrand.

### Previous (incorrect) conclusion

~~The regression is caused by the Symmetria C++ plugin having a pathological initialization
issue that the Caelestia C++ plugin does not have.~~

```
GOOD (0.65s):  b96b3fd  style(bar): apply glassmorphism pill effect to Workspaces
                         ↓  (uses Caelestia.* plugin)
BAD  (23.0s):  0fbdbed  refactor: rebrand Caelestia to Symmetria
                         ↓  (uses Symmetria.* plugin)
```

**This is NOT a QML issue.** The QML code is functionally identical before and after the
rebrand. The ONLY change is the C++ plugin namespace: `Caelestia.*` → `Symmetria.*`.

---

## HOW WE KNOW THIS — Complete Methodology

### Measurement Protocol

Every measurement follows this protocol:

1. **Kill all instances:** `pkill qs` (NOT `pkill quickshell` — the binary is `qs`)
2. **Verify clean:** `pgrep -fa "qs -c" | grep -v grep | grep -v zsh | grep -v python | grep -v claude`
3. **Run shell:** `qs -c <config> > /tmp/log.log 2>&1 &`
4. **Wait for 3 heartbeats** (confirms event loop unblocked)
5. **Extract timing:** `ShellRoot @ T0` to `HB #1 @ T1` = freeze duration
6. **Kill:** `kill $PID; wait $PID; sleep 3`
7. **Repeat 3 times**, report all values

**Heartbeat profiler** (added to each test shell.qml):
```qml
Component.onCompleted: console.log("[BOOT] ShellRoot @ " + Date.now())
Timer {
    interval: 500; running: true; repeat: true; property int b: 0
    onTriggered: {
        b++; console.log("[BOOT:HB] #" + b + " @ " + Date.now());
        if (b >= 5) Qt.exit(0);  // Auto-exit for benchmarks
    }
}
```

The freeze duration ≈ T1 - T0 (the 500ms timer delay is negligible vs 20+ second freezes).

### Critical Process Management Discovery

The QuickShell binary is `qs`, NOT `quickshell`. For the first half of this investigation,
we used `pkill -x quickshell` and `pgrep -x quickshell` — which matched NOTHING. This
caused orphaned instances to accumulate, producing 50-84 second measurements that were
actually 2-4 instances competing for resources. The true single-instance time is ~23s.

**Correct commands:**
- Kill: `pkill qs`
- Check: `pgrep -fa "qs -c" | grep -v grep | grep -v zsh | grep -v python | grep -v claude`
- Kill specific config: `pkill -f "qs -c symmetria$"` (with `$` anchor)
- Note: `qs -c symmetria-fm` (file manager) also matches — filter it if needed

### Worktree-Based Git Bisection

To test historical commits without modifying the working tree:

```bash
# Create worktree for a specific commit
git worktree add /tmp/qs-bisect-<name> <commit-hash>

# Fix C++ plugin import paths (older commits use Caelestia.*, not Symmetria.*)
find /tmp/qs-bisect-<name> -name "*.qml" -exec sed -i \
    -e 's/import Caelestia\.Models/import Symmetria.FileManager.Models/g' \
    -e 's/import Caelestia\.Internal/import Symmetria.Internal/g' \
    -e 's/import Caelestia\.Services/import Symmetria.Services/g' \
    -e 's/import Caelestia$/import Symmetria/g' \
    -e 's/import Symmetria\.Models/import Symmetria.FileManager.Models/g' \
    -e 's/import YaziFM\.Models/import Symmetria.FileManager.Models/g' \
    {} \;

# Add heartbeat profiler to shell.qml (inject after "ShellRoot {")
sed -i '/ShellRoot {/a\    Component.onCompleted: console.log("[BOOT] ShellRoot @ " + Date.now())\n    Timer { interval: 500; running: true; repeat: true; property int b: 0; onTriggered: { b++; console.log("[BOOT:HB] #" + b + " @ " + Date.now()); if (b >= 5) Qt.exit(0); } }' /tmp/qs-bisect-<name>/shell.qml

# Ensure QtQuick is imported (needed for Timer)
grep -q "import QtQuick" /tmp/qs-bisect-<name>/shell.qml || \
    sed -i 's/import Quickshell/import Quickshell\nimport QtQuick/' /tmp/qs-bisect-<name>/shell.qml

# Create QuickShell config symlink
ln -sfn /tmp/qs-bisect-<name> ~/.config/quickshell/symmetria-bisect

# Run benchmark
qs -c symmetria-bisect > /tmp/log.log 2>&1 &

# Clean up when done
git worktree remove /tmp/qs-bisect-<name>
```

**Plugin path compatibility:** Commits before `035397a` (position #53) use `Symmetria.Models`
or `Caelestia.Models`. The installed plugin is at `Symmetria.FileManager.Models`. The sed
command above fixes all known path variants.

**Import "QtQuick":** Early commits don't import QtQuick in shell.qml (Caelestia didn't
need it). The Timer component requires it. The sed command adds it if missing.

---

## COMPLETE BISECTION DATA

All measurements on fresh system (post-reboot, load avg < 2.5, single instance, 3 runs each):

### Phase 1: Establishing baselines

| Shell/Commit | Position | Description | Run 1 | Run 2 | Run 3 | Median |
|---|---|---|---|---|---|---|
| Caelestia (upstream repo) | — | Pure upstream, Caelestia plugin | 0.622s | 0.628s | 0.610s | **0.62s** |
| Symmetria `main` (current) | #1 | Full shell, Symmetria plugin | 23.2s | 23.0s | 22.6s | **23.0s** |
| Symmetria, no notifications | #1 | shell.qml: NotificationsOverlay commented out | 23.3s | 22.4s | 21.8s | **22.4s** |
| Symmetria, sourceComponent v2 | #1 | Panels: Loaders with active:false | 23.1s | 24.3s | 21.9s | **23.1s** |
| Symmetria, caelestia-equiv shell.qml | #1 | Only Background+Drawers+AreaPicker+Lock | 23.1s | 24.7s | 22.9s | **23.1s** |
| Symmetria, caelestia-equiv Panels | #1 | Stripped to only session/launcher/sidebar/utilities/bar.popouts | 24.9s | 22.0s | 23.2s | **23.2s** |

### Phase 2: Git bisection (binary search)

| Commit | Position | Description | Run 1 | Run 2 | Run 3 | Median |
|---|---|---|---|---|---|---|
| `25572b7` | #410 | Fork point (first commit) | 0.685s | 0.635s | 0.627s | **0.65s** |
| `9a8b686` | #350 | Glassmorphism StatusIcons | 0.654s | 0.661s | 0.661s | **0.66s** |
| `5e8b175` | #320 | Clipboard grid navigation | 0.644s | 0.653s | 0.649s | **0.65s** |
| `7e5a10f` | #312 | CI flake update | 0.644s | 0.657s | 0.636s | **0.64s** |
| `66c3a5d` | #309 | **Shapes refactor** | 0.657s | 0.630s | 0.650s | **0.65s** |
| `b96b3fd` | #308 | **Glassmorphism workspaces** | 0.655s | 0.640s | 0.653s | **0.65s** |
| **`0fbdbed`** | **#307** | **REBRAND: Caelestia → Symmetria** | **23.5s** | **21.9s** | **23.9s** | **23.1s** |
| `c3b43e5` | #306 | HyprWhspr STT drawer | — | — | — | still bad (after rebrand) |
| `79fcf07` | #290 | HyprWhspr wave animation | 24.8s | 23.2s | 25.4s | **24.4s** |
| `eac6b65` | #230 | KeyChords grid alignment | 22.9s | 24.9s | 23.0s | **23.0s** |
| `695597e` | #52 | ClientAppIcon consolidation | 23.4s | 25.1s | 28.6s | **25.1s** |

### Bisection convergence

```
Fork (#410)     0.65s  ✓ GOOD
  ↓ 60 commits
#350            0.66s  ✓ GOOD
  ↓ 30 commits
#320            0.65s  ✓ GOOD
  ↓ 8 commits
#312            0.64s  ✓ GOOD
  ↓ 3 commits
#309 (shapes)   0.65s  ✓ GOOD
  ↓ 1 commit
#308 (glass)    0.65s  ✓ GOOD
  ↓ 1 commit
#307 (REBRAND)  23.1s  ✗ BAD  ← THE COMMIT
  ↓ ...
#290            24.4s  ✗ BAD
  ↓ ...
#1 (HEAD)       23.0s  ✗ BAD
```

---

## WHY THE REBRAND CAUSED A 35x REGRESSION

### What the rebrand commit does

Commit `0fbdbed` replaces all occurrences of `Caelestia` with `Symmetria` in QML import
statements:

```diff
- import Caelestia
+ import Symmetria

- import Caelestia.Internal
+ import Symmetria.Internal

- import Caelestia.Services
+ import Symmetria.Services

- import Caelestia.Models
+ import Symmetria.Models  (later changed to Symmetria.FileManager.Models)
```

The QML code is UNCHANGED. Only the C++ plugin namespace changes.

### The two C++ plugins

| Plugin | Location | Built against |
|--------|----------|---------------|
| `Caelestia` | Local install: `~/projects/shell-benchmarks/caelestia-shell/install/usr/lib/qt6/qml/Caelestia/` | Qt 6.10.2 |
| `Symmetria` | System: `/usr/lib/qt6/qml/Symmetria/` | Qt 6.10.2 |

Both plugins were compiled against the same Qt version (6.10.2) on the same system.
Both provide similar types (CircularBuffer, ImageAnalyser, etc.). The Symmetria plugin
is a FORK of the Caelestia plugin with minimal changes.

### The plugin modules

Both provide three QML modules:
- Main (`Symmetria` / `Caelestia`): App database, requests, toaster, qalculator
- Internal (`Symmetria.Internal` / `Caelestia.Internal`): CircularBuffer, image analysis
- Services (`Symmetria.Services` / `Caelestia.Services`): Audio-related C++ types

Additionally, Symmetria has a fourth module from a separate project:
- `Symmetria.FileManager.Models`: FileSystemModel (from symmetria-file-manager)

### Hypothesis: Plugin initialization cost

The Symmetria plugin's `QQmlExtensionPlugin::registerTypes()` or module initialization
might be doing something expensive that the Caelestia plugin doesn't:
- Database initialization (AppDB)
- D-Bus service registration
- File system scanning
- Network requests

**Next step:** Compare the C++ source code of both plugins to find the initialization
difference. The source is at:
- Caelestia: `~/projects/shell-benchmarks/caelestia-shell/plugin/src/Caelestia/`
- Symmetria: `/home/jc/.config/quickshell/symmetria/plugin/src/`

---

## WHAT WE TRIED AND WHY IT DIDN'T WORK

### Approach 1: sourceComponent + active:false

**Hypothesis:** Wrap panels in `Loader { active: false; sourceComponent: Module.Wrapper {} }`
and defer instantiation via Timer.

**Result:** 23.1s (same as baseline). Zero effect.

**Why it failed:** `sourceComponent:` forces type compilation during `beginCreate()` even
with `active: false`. Only INSTANTIATION is deferred. But the freeze is from the C++ plugin
initialization triggered by the type compilation, not from QML instantiation.

### Approach 2: setSource with URLs

**Hypothesis:** `Loader.setSource("../session/Wrapper.qml", {props})` defers BOTH compilation
and instantiation.

**Result:** Panels load in ~1s after Timer fires. But total time still ~23s because
`Backgrounds.qml` imports the same modules, triggering plugin init anyway.

**Additional bug:** Wrapper files loaded via setSource can't resolve sibling types
(`Content.qml`). Adding `import "."` doesn't fix it — the `qs:@/` URL scheme prevents
directory import resolution. Error: "Content is not a type".

### Approach 3: Dynamic Backgrounds (Qt.createComponent in Timer)

**Hypothesis:** Remove module imports from Backgrounds.qml, dynamically create Background
ShapePaths via `Qt.createComponent(url).createObject()`.

**Result:** Background.qml files load fine (they don't import `qs.modules.*`), but the
plugin is still initialized through other import paths (services, components).

### Approach 4: Dashboard removal

**Result:** Removed 1,146 bindings (7% of total). No measurable improvement — within ±1s
measurement noise.

### Approach 5: Notification D-Bus blocker removal

**Result:** 0.6s improvement. The D-Bus notification registration (~19s) runs in parallel
with the main freeze and is fully overlapped. Removing it only saves the non-overlapped tail.

### Approach 6: Stripping to caelestia-equivalent

**Result:** Removed ALL extra modules from Panels/Backgrounds/Drawers/shell.qml (clipboard,
askpass, stt, calculator, packages, agentbar, keychords, keycaster, killconfirm). Still 23s.
The extra modules aren't the cause — the C++ plugin is.

---

## PROFILING DATA

### Binding statistics (from QML_SHOW_UNIT_STATS=1)

| Metric | Caelestia | Symmetria | Ratio |
|--------|-----------|-----------|-------|
| Files compiled | 247 | 316 | 1.28x |
| Total bindings | 13,142 | 16,613 | 1.26x |
| Total objects | 4,805 | 5,962 | 1.24x |
| **Startup time** | **0.6s** | **23s** | **38x** |

The 1.26x more bindings cannot explain the 38x slowdown. The per-binding cost is 31x
higher in Symmetria, indicating the C++ plugin initialization dominates.

### Top module binding costs

| Module | Bindings | Files | Notes |
|--------|----------|-------|-------|
| dashboard | 1,146 | 12 | REMOVED (was disabled) |
| components | 968 | 40 | Shared, can't defer |
| bar | 950 | 23 | Always visible |
| lock | 722 | 7 | Always compiled |
| utilities | 447 | 8 | |
| notifications | 352 | 2 | D-Bus overlapped |
| config | 330 | 25 | Shared |
| launcher | 257 | 8 | |
| controlcenter | 228 | 7 | |

### perf profile (CPU function breakdown)

**Symmetria** — top functions during startup (all in `libQt6Qml.so.6.10.2`):
```
5.55%  QQmlJavaScriptExpression::evaluate()
5.28%  QV4::Lookup::getterQObject()
5.23%  QV4::ArrayData::realloc()         ← frequent array creation
4.05%  QQmlVMEMetaObject::metaCall()
3.02%  QV4::SimpleArrayData::length()
2.79%  QQmlPropertyCapture::captureNonBindableProperty()
2.59%  [unknown QML function]
2.05%  QV4::QmlListWrapper::virtualGet()
```

**Caelestia** — top function during capture (shell starts so fast the profiler captures
mostly post-startup runtime work):
```
5.84%  fftw_cpy2d (audio visualizer FFT — NOT startup)
```

QML binding evaluation doesn't even register at >2% for Caelestia. The entire 23s in
Symmetria is spent in QML binding evaluation, which is triggered by the C++ plugin
initialization cascade.

---

## ENVIRONMENT AND TOOLS

### Caelestia benchmark setup

```bash
# Clone and build
git clone --depth 1 https://github.com/caelestia-dots/shell.git ~/projects/shell-benchmarks/caelestia-shell
cd ~/projects/shell-benchmarks/caelestia-shell
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=$HOME/projects/shell-benchmarks/caelestia-shell/install \
    -DVERSION=0.1.0
cmake --build build
cmake --install build

# Create QuickShell config
ln -sfn ~/projects/shell-benchmarks/caelestia-shell ~/.config/quickshell/caelestia-bench

# Run with local plugin
QML2_IMPORT_PATH="$HOME/projects/shell-benchmarks/caelestia-shell/install/usr/lib/qt6/qml" \
    qs -c caelestia-bench
```

### end-4/dots-hyprland

Cloned but could NOT benchmark — their `main` branch has an empty `modules/common/widgets/shapes/`
directory causing "module not installed" errors. No build/setup script found.
File count: 574 QML files (65% more than Symmetria, uses separate-windows + LazyLoader architecture).

### Qt/QML profiling environment variables

| Variable | Purpose |
|----------|---------|
| `QML_IMPORT_TRACE=1` | Logs every import resolution step |
| `QML_SHOW_UNIT_STATS=1` | Prints object/binding/bytecode counts per compiled QML file |
| `QSG_RENDER_TIMING=1` | Per-frame polish/sync/render/swap timing |
| `QV4_SHOW_BYTECODE=1` | Dumps compiled V4 bytecode (very verbose) |
| `QV4_PROFILE_WRITE_PERF_MAP=1` | Writes `/tmp/perf-<pid>.map` for `perf` symbol resolution |

Full profiling reference: `09-profiling-tools-reference.md`

---

## NEXT STEPS

### 1. Compare plugin source code (IMMEDIATE)

Diff the Symmetria and Caelestia C++ plugin sources to find the initialization difference:

```bash
diff -r ~/projects/shell-benchmarks/caelestia-shell/plugin/src/Caelestia/ \
        plugin/src/ \
        --exclude=CMakeLists.txt --exclude="*.hpp"
```

Key files to compare:
- Main plugin init: `plugin/src/Symmetria/*.cpp` vs `Caelestia/*.cpp`
- Services module: `plugin/src/Symmetria/Services/` vs `Caelestia/Services/`
- Internal module: `plugin/src/Symmetria/Internal/` vs `Caelestia/Internal/`

### 2. Test with Caelestia plugin on Symmetria code (QUICK VALIDATION)

If we change Symmetria's QML imports back to `Caelestia.*` (using the same sed commands
from bisection) and run with `QML2_IMPORT_PATH` pointing to the Caelestia plugin, the
startup should drop to ~0.6s. This would CONFIRM the plugin is the sole cause.

### 3. Profile plugin initialization (DETAILED)

```bash
# Use perf to capture plugin init specifically
perf record -g -e cpu/cycles/Pu -- timeout 30 qs -c symmetria
perf report --stdio --no-children --percent-limit 1

# Or use strace to find blocking syscalls during init
strace -T -e trace=network,ipc -f timeout 30 qs -c symmetria 2>&1 | head -100
```

### 4. Check Symmetria.FileManager.Models plugin

The fourth module (`Symmetria.FileManager.Models`) is from the separate
`symmetria-file-manager` project. It provides `FileSystemModel` which might do
filesystem scanning at initialization. This module doesn't exist in Caelestia.

### 5. Rebuild Symmetria plugin from scratch

```bash
cd /home/jc/.config/quickshell/symmetria
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/ \
    -DINSTALL_QSCONFDIR=$HOME/.config/quickshell/symmetria
cmake --build build
sudo cmake --install build
sudo chown -R $USER:$USER ~/.config/quickshell/symmetria
```

---

## COMPLETE TIMELINE OF INVESTIGATION

### Session 1 (earlier today, pre-reboot)

1. **Initial goal:** Defer panel loading to reduce startup time
2. **Approach:** sourceComponent + active:false → zero effect
3. **Approach:** setSource with URLs → panels load in 1s BUT sibling types break
4. **Discovery:** `pkill quickshell` was wrong — process is `qs`. All measurements contaminated.
5. **Discovery:** Multiple instances caused 50-84s measurements (actual was ~23s)

### Session 2 (post-reboot, clean system)

6. **Reliable baseline:** 23.0s (3 runs, single instance, fresh system)
7. **sourceComponent v2 confirmed:** zero effect (23.1s)
8. **Notification removal:** 0.6s improvement (D-Bus overlapped)
9. **Dashboard removal:** within noise
10. **Caelestia benchmark:** **0.6s** — same architecture, 38x faster!
11. **Profiling:** 316 files, 16,613 bindings vs caelestia's 247/13,142. Ratio 1.26x but time 38x.
12. **Stripping Symmetria to caelestia-equivalent:** still 23s — extra modules aren't the cause
13. **perf:** All time in QML binding evaluation, no single pathological function
14. **Git bisection:** 410 commits → narrowed to 7 → narrowed to 1: commit `0fbdbed`
15. **Root cause:** The `Caelestia.*` → `Symmetria.*` plugin namespace change

### Session 3 (night, same day — CORRECTED ROOT CAUSE)

16. **Re-validation:** Confirmed bisection data (GOOD=698ms, BAD=24.0s)
17. **Discovery:** Both worktrees have identical Symmetria imports after patching
18. **Discovery:** The ONLY non-namespace difference is `Paths.*` pointing to `caelestia/` vs `symmetria/`
19. **Test: empty JSON config** → 670ms (NOT the config file)
20. **Test: full config + fake state dir** → 686ms (NOT the config file)
21. **Test: rename notifs.json** → 704ms — **FOUND THE FILE**
22. **Test: restore notifs.json** → 24.5s — **CONFIRMED**
23. **Analysis:** 6,890 notifications, each `push()` triggers O(n) filter on `notClosed`/`popups` = O(n²)
24. **Fix:** `root.list = loaded` (batch assignment) → **976ms** (23.6x improvement)

### Scaling data (notifications vs. freeze time)

| Notifications | Freeze | Per-notif cost |
|--------------|--------|---------------|
| 0 | 670ms | — |
| 100 | 716ms | 0.5ms |
| 500 | 772ms | 0.2ms |
| 1000 | 1,032ms | 0.4ms |
| 6890 | 24,000ms | 3.4ms |

The super-linear growth (0.2ms → 3.4ms per notification) confirms O(n²) behavior.

### Key learnings

- Single measurements are unreliable (±2s variance). Always 3+ runs.
- The process is `qs`, not `quickshell`. Wrong name = orphaned instances.
- The `qs -c symmetria-fm` file manager matches `pgrep -f "qs -c"` — filter it.
- Module directory imports are all-or-nothing (use ONE type → compile ALL files).
- `sourceComponent` compiles types eagerly (even with active:false).
- `setSource` breaks sibling type resolution (Content.qml not found).
- Binding count ≠ cost. 1.26x bindings caused 38x time = cascade amplification.
- The upstream (caelestia) is the ground truth for "this architecture CAN be fast."
- Git bisection with worktrees is the most reliable way to find regressions.
- **When a bisection points to a refactor/rename commit, check RUNTIME SIDE EFFECTS (state paths, config paths) not just the code changes.**
- **QML list property mutation (push/splice) in loops is O(n²) when computed properties bind to the list.** Always batch-build and assign once.

---

## THE FIX

### `services/Notifs.qml` — Batch notification loading

**Before (O(n²)):**
```qml
onLoaded: {
    const data = JSON.parse(text());
    for (const notif of data)
        root.list.push(notifComp.createObject(root, notif));  // ← triggers bindings per push
    root.list.sort((a, b) => b.time - a.time);
    root.loaded = true;
}
```

**After (O(n)):**
```qml
onLoaded: {
    const data = JSON.parse(text());
    const loaded = [];
    for (const notif of data)
        loaded.push(notifComp.createObject(root, notif));  // ← local array, no bindings
    loaded.sort((a, b) => b.time - a.time);
    root.list = loaded;  // ← single assignment, single binding evaluation
    root.loaded = true;
}
```

**Result:** 23,000ms → 976ms (6,890 notifications)

### Why push() was O(n²)

Two computed properties bind to `list`:
```qml
readonly property list<Notif> notClosed: list.filter(n => !n.closed)
readonly property list<Notif> popups: list.filter(n => n.popup)
```

Each `root.list.push()` triggers a change notification on `list`, which causes both
`notClosed` and `popups` to re-evaluate their filter expressions over the entire list.
For n pushes: n × filter(1..n items) = n²/2 filter operations per property.

With 6,890 notifications: 2 × (6,890² / 2) ≈ **47.5 million** filter iterations.
