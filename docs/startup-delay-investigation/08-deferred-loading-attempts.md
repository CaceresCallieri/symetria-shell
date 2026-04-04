# Deferred Loading Attempts (2026-04-04, Session 2)

**Branch:** `fix/deferred-panels-v2`
**Qt:** 6.10.2 (pinned), **Quickshell:** r125 (854088c)
**System:** Same as investigation. CPU temp reached 78°C during testing (5.09GHz max, ~4.47GHz throttled).

## Critical Measurement Issues Discovered

### Non-deterministic timing
Startup times vary significantly between runs under seemingly identical conditions.
**A single measurement is NOT a reliable baseline.** Future experiments must use
3+ runs and report min/median/max.

### Multiple instance contamination (ROOT CAUSE of bad measurements)
The QuickShell binary is `qs`, NOT `quickshell`. All kill/check commands in this session
used `pkill -x quickshell` / `pgrep -x quickshell` — which matched NOTHING. Every "verified
clean" state was a false positive. At various points, 2-5 concurrent `qs -c symmetria`
instances were running simultaneously, causing 2-4x slowdown from layer-shell contention.

**ALL measurements >30s in this session are invalid.** The only trustworthy measurements
are the first two (20.3s and 21.7s), taken before the accumulation of orphaned instances.

To kill QuickShell: `pkill qs` (NOT `pkill quickshell`).
To verify: `pgrep -fa qs | grep -v grep | grep -v zsh | grep -v python | grep -v claude`.

### QML cache is not used
`~/.cache/quickshell/qmlcache/` remains at 4KB (1 file) after full shell startup.
Quickshell r125 does not populate this cache. Clearing it has no effect on timing.
The investigation's "QML cache NOT a factor" finding is confirmed — because the cache
isn't being used at all.

## Approaches Tested

### 1. sourceComponent + active: false (v2)

**Hypothesis:** `Loader { active: false; sourceComponent: Session.Wrapper { ... } }` defers
instantiation. The Loader is created during `beginCreate()` but the sourceComponent content
is not instantiated until `active` becomes `true` (via Timer).

**Result:** ~20s (single measurement, first test of the session)

**Issue:** We assumed this was "no improvement" because we compared against the investigation's
"22s" number. But the investigation's timing was measured with a DIFFERENT quickshell version
(r110 on Qt 6.11.0, not r125 on Qt 6.10.2). The actual baseline for today's conditions was
never established with multiple runs.

**Technical finding:** `sourceComponent:` inline declarations trigger TYPE COMPILATION during
`beginCreate()` even when the Loader's `active` is `false`. Only INSTANTIATION is deferred.
The ~20s is likely the compilation cost; instantiation is deferred to after the Timer fires.

**Bug found:** `sidebar: sidebar` inside `sourceComponent: Utilities.Wrapper { ... }` creates
a binding loop — QML resolves the right-hand `sidebar` to the Wrapper's own `required property`
instead of the outer Loader id. Fix: use `sidebar: root.sidebar`.

### 2. setSource with relative paths (v3)

**Hypothesis:** `setSource("../session/Wrapper.qml", {...})` defers BOTH compilation AND
instantiation, since the URL string isn't resolved until the Timer fires.

**Result:** ~22s (single measurement)

**Confirmed:** None of the 10 Wrapper files import `qs.modules.*` — they only use
`qs.components`, `qs.config`, `Quickshell`, `QtQuick`. So setSource with relative paths
is viable for all Wrappers.

**Technical finding:** The ~22s is NOT from Panels at all. The existing `06-test-results.md`
already shows "Import-Only Test (Drawers with imports, no components): 18.9s". The imports
in other files in the `drawers/` directory (Backgrounds.qml, Interactions.qml) and the
BarWrapper → Bar cascade still execute during `beginCreate()`.

### 3. Empty Panels stub

**Hypothesis:** If Panels is 99% of the freeze, an empty stub should give ~672ms.

**Result:** ~53s (single measurement, likely contaminated by orphaned instance)

**Issue:** The 672ms from the investigation was measured in the `qs-startup-bench` config,
not the full shell. The benchmark loaded ONLY Drawers — no Background, no Notifications,
no other shell.qml modules. The "672ms" is not comparable to a full shell measurement.

### 4. Combined: setSource Panels + deferred ControlCenter/WindowInfo

**Change:** Panels uses setSource (9 module imports removed). `bar/popouts/Wrapper.qml`
has `sourceComponent: ControlCenter { ... }` and `sourceComponent: WindowInfo { ... }`
replaced with on-demand `setSource()` triggered by `onShouldBeActiveChanged`.

**Result:** Timer fires 51-69s after ShellRoot, then panels load in **~1s** after Timer.
Total still 52-69s (contaminated by multiple instances in most runs).

**Key finding:** The panel setSource IS working — panels compile and instantiate in ~1s
after the Timer fires. The 50-60s `beginCreate()` phase is from OTHER components
(Backgrounds, Bar, Interactions, other shell.qml modules).

### 5. Baseline: original code — CLEAN 3-RUN MEASUREMENT (post-reboot)

After rebooting (load 1.17, clean system), with `pkill qs` (correct process name):

| Run | Original | v2 + no dashboard | No notifications |
|-----|----------|-------------------|------------------|
| 1   | 23.2s    | 23.1s             | 23.3s            |
| 2   | 23.0s    | 24.3s             | 22.4s            |
| 3   | 22.6s    | 21.9s             | 21.8s            |
| **Median** | **23.0s** | **23.1s** | **22.4s** |

**Conclusions from clean measurements:**
- sourceComponent v2 (deferred instantiation): **ZERO measurable effect** (~23s = same as baseline)
- Dashboard removal (1,146 bindings): **within noise** (~0s savings)
- Notification removal (D-Bus blocker): **0.6s savings** (D-Bus is fully overlapped by QML)
- The ~23s is dominated by QML compilation + binding evaluation in `beginCreate()`
- The D-Bus notification blocker (~19s) runs in parallel and is hidden beneath the QML cascade

**Earlier measurements (50-68s) were ALL contaminated** by running multiple `qs` instances.
The `pkill -x quickshell` command was targeting the wrong process name (should be `pkill qs`).

## What We Learned About the Architecture

### The freeze is in Qt's `beginCreate()`

QuickShell's C++ source confirms: the reload walk (`EngineGeneration::onReload()`) is O(n)
and trivial on first startup. The freeze is entirely within `QQmlComponent::beginCreate()`,
which synchronously compiles and instantiates the entire component tree.

### `sourceComponent:` triggers compilation during `beginCreate()`

Even with `active: false`, the type referenced in `sourceComponent: Foo { ... }` must be
compiled (parsed, bytecode generated) during the enclosing file's compilation. The QML engine
uses lazy type compilation (import just registers names), but a type REFERENCE forces compilation.

### The import cascade in `drawers/` is the core issue

When `Drawers.qml` is compiled, QML scans the `drawers/` directory and registers all types.
Files like `Backgrounds.qml` (which imports 12 module namespaces and references Background
types from each) and `Interactions.qml` (which imports `bar.popouts`) are compiled as part
of this directory scan. Each of these triggers further compilation cascades.

From `06-test-results.md`: "Import-Only Test (Drawers with ALL 12+ imports, bare StyledWindow):
18.9s" — the imports ALONE cause the freeze.

### end-4/dots-hyprland avoids this with separate windows

end-4 (574 QML files, larger than Symmetria's 348) uses:
- Separate `PanelWindow` per module (no unified window)
- `LazyLoader` wrapping each module (`PanelLoader` component)
- No unified `Backgrounds.qml` that imports every module
- 3-tier loading: PanelFamily → Module → Per-Monitor

This eliminates the single-file import cascade that causes our freeze.

### The unified Backgrounds.qml is an architectural trap

Symmetria's signature visual (panels emerging from a unified shell border) requires
`Backgrounds.qml` to import ALL module types for its `Shape` + `ShapePath` rendering.
This forces every module to be compiled in a single `beginCreate()` call.

## Clean Measurement Summary (post-reboot, 3 runs each, single instance)

| Configuration | Median | vs Baseline |
|--------------|--------|-------------|
| **Original (baseline)** | **23.0s** | — |
| sourceComponent v2 + no dashboard | 23.1s | ~0% (no effect) |
| No notifications (D-Bus removed) | 22.4s | -3% (D-Bus is overlapped) |

**Key conclusions:**
- `sourceComponent` + `active: false` defers instantiation but NOT compilation → no savings
- `setSource()` with URLs breaks sibling type resolution (`Content is not a type`) → unusable
- The D-Bus notification blocker (~19s) is fully overlapped by QML cascade (~23s) → removing it saves only ~0.6s
- Module directory imports compile ALL files (all-or-nothing) → can't selectively defer via imports
- The 23s is pure `beginCreate()` cost: 316 files, 16,613 bindings, 5,962 objects

## Profiling Data (from QML_SHOW_UNIT_STATS)

316 QML files compiled with 16,613 total bindings. Top modules by binding cost:

| Module | Bindings | Files | Notes |
|--------|----------|-------|-------|
| dashboard | 1,146 | 12 | DISABLED (removed in this branch) |
| components | 968 | 40 | Shared, cannot defer |
| bar | 950 | 23 | Always visible |
| lock | 722 | 7 | Always compiled |
| utilities | 447 | 8 | |
| notifications | 352 | 2 | D-Bus blocker overlapped |
| config | 330 | 25 | Shared |
| launcher | 257 | 8 | |
| controlcenter | 228 | 7 | |

## What Would Actually Help

1. **Separate windows per module** (end-4 architecture) — eliminates the import cascade.
   Each module loads independently via LazyLoader. Proven at 574 files with no freeze.
   Requires rewriting the unified Backgrounds.qml Shape system.

2. **QuickShell upstream: make `qs.modules.*` work in URL-loaded files** — would enable
   `setSource()` to truly defer compilation. Currently, loaded files can't resolve sibling
   types or module paths, making setSource unusable for Wrapper components.

3. **QuickShell upstream: non-blocking D-Bus registration** — would remove the 19s floor.
   Currently `Quickshell.Services.Notifications` blocks atomically during `beginCreate()`.

4. **Reduce total binding count** — at ~1.4ms/binding, removing 3,000 bindings saves ~4s.
   Targets: lock module (722 bindings, not needed at startup), unused/disabled features.

5. **Test quickshell r110 on Qt 6.10.2** — investigation measured 17-18s with r110.
   15 commits between r110→r125 may include a regression (23s vs 17s), but commit
   review shows no obvious performance changes. Difference may be measurement conditions.
