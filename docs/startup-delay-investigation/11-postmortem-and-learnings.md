# Startup Delay Investigation — Postmortem & Learnings

**Duration:** 2026-04-04 (3 sessions across one day)
**Impact:** 23-second startup freeze → 976ms (23.6x improvement)
**Fix:** 1 line change in `services/Notifs.qml`
**Commit:** `fe99f12`

---

## What Happened

Symmetria Shell froze for 23 seconds on every startup. The event loop was completely
blocked — no rendering, no input, no timers firing — until the freeze ended.

### Root Cause

`services/Notifs.qml` deserialized 6,890 persisted notifications using `root.list.push()`
in a loop. Each `push()` triggered change notifications on the `list` property, which caused
two computed filter properties to re-evaluate over the entire growing list:

```qml
property list<Notif> list: []
readonly property list<Notif> notClosed: list.filter(n => !n.closed)
readonly property list<Notif> popups: list.filter(n => n.popup)

// In onLoaded:
for (const notif of data)
    root.list.push(notifComp.createObject(root, notif));  // O(n) per push × n pushes = O(n²)
```

**Cost:** 6,890 pushes × 2 filters × average n/2 items = ~47.5 million filter iterations.

### The Fix

```qml
const loaded = [];
for (const notif of data)
    loaded.push(notifComp.createObject(root, notif));  // local array, no bindings
loaded.sort((a, b) => b.time - a.time);
root.list = loaded;  // single assignment = 2 filter evaluations total
```

### Why It Took 3 Sessions To Find

The bug is invisible in the source code. `push()` in a loop is normal JavaScript. The
O(n²) cost comes from QML's reactive binding system, which is an implicit, declarative
layer on top of the imperative code. There's no syntax or compiler warning that says
"this push will trigger 6,890 binding re-evaluations."

Additionally, the bug is **data-dependent** — it only manifests with thousands of
accumulated notifications. A fresh install (zero notifications) starts in 670ms. The
investigation started by looking at architecture and code, not at runtime data.

---

## Investigation Timeline

### Session 1: Wrong Process Name (~4 hours wasted)

| Step | Action | Result | Problem |
|------|--------|--------|---------|
| 1 | Defer panels with `sourceComponent` + `active:false` | 23.1s (no change) | sourceComponent compiles eagerly |
| 2 | Defer panels with `setSource()` URLs | Panels load in 1s BUT sibling types break | `qs:@/` URL scheme prevents directory imports |
| 3 | Kill shell with `pkill quickshell` | No processes killed | Binary is `qs`, not `quickshell` |
| 4 | Run more experiments | 50-84s measurements | Orphaned instances accumulating |

**Time lost:** ~4 hours. All measurements after step 3 were contaminated by multiple
instances. The fundamental problem was never identified because the measurement tool
was broken.

### Session 2: Correct Bisection, Wrong Conclusion (~3 hours)

| Step | Action | Result | Insight |
|------|--------|--------|---------|
| 5 | Reliable baseline (3 runs, single instance) | 23.0s | True baseline established |
| 6 | Benchmark Caelestia upstream | 0.6s | Same architecture, 38x faster |
| 7 | Profile bindings | 1.26x more bindings, 38x slower | Per-binding cost 31x higher |
| 8 | Strip Symmetria to caelestia-equivalent | Still 23s | Extra modules not the cause |
| 9 | Git bisect 410 commits | Commit `0fbdbed` (rebrand) | Boundary identified |
| 10 | Conclude: "C++ plugin is the cause" | **WRONG** | Misinterpreted the rebrand |

**The error:** The bisection correctly identified the rebrand commit, but we concluded
the C++ plugin namespace change was the cause. We didn't notice that `Paths.state` also
changed from `caelestia/` (non-existent) to `symmetria/` (with 2.2MB of notifications).

### Session 3: Correct Root Cause (~1.5 hours)

| Step | Action | Result | Insight |
|------|--------|--------|---------|
| 11 | Re-validate bisection | GOOD=698ms, BAD=24.0s | Confirmed |
| 12 | Notice both worktrees have identical imports | Both use Symmetria plugin | Plugin can't be the cause |
| 13 | Test with empty config | 670ms | Config isn't the cause |
| 14 | Test with fake state directory | 686ms | State files matter |
| 15 | Rename `notifs.json` | 704ms | **THE FILE** |
| 16 | Restore `notifs.json` | 24.5s | Confirmed |
| 17 | Analyze: 6,890 notifications, O(n²) push loop | Math checks out | Root cause found |
| 18 | Fix: batch assignment | 976ms | **23.6x improvement** |

---

## Mistakes Made & Lessons Learned

### Mistake 1: Not Testing With Clean State First

**What happened:** We spent hours on QML architecture (Loader wrapping, setSource,
dynamic Backgrounds) before checking if the problem was data-dependent.

**The 30-second test that would have found it:**
```bash
mv ~/.local/state/symmetria/notifs.json /tmp/ && qs -c symmetria  # → 0.7s
mv /tmp/notifs.json ~/.local/state/symmetria/                      # → 23s
```

**Lesson:** Before any architectural investigation, test with empty/missing state files.
If removing user data fixes the problem, the issue is data loading, not code structure.

### Mistake 2: Wrong Process Name

**What happened:** Used `pkill quickshell` and `pgrep quickshell` throughout Session 1.
The binary is `qs`. No processes were ever killed. Orphaned instances accumulated silently.

**The cost:** ~4 hours of invalid measurements, misleading data, confusion.

**Lesson:** Before any benchmark session, verify: what is the binary name? How do you
kill it? How do you confirm it's dead? Document this in CLAUDE.md (we did, afterwards).

### Mistake 3: Interpreting Bisection Results Too Narrowly

**What happened:** Bisection found the rebrand commit. We looked at what the commit
*explicitly changed* (import namespaces) and stopped there. We didn't consider what
the commit *implicitly changed* (runtime state paths that resolve to different data).

**The trap:** A rename commit changes strings everywhere. Each string might resolve to
a different runtime resource. The `import Caelestia` → `import Symmetria` change was
obvious and high-profile. The `caelestia/` → `symmetria/` path change in `Paths.qml`
was hidden in the noise of the rename.

**Lesson:** When bisection points to a refactor/rename commit, enumerate ALL paths and
resource references that changed. For each one, check: does the old path exist? Does the
new path exist? What's at each location? How much data?

### Mistake 4: Asymmetric Test Setup

**What happened:** When testing pre-rebrand commits, we patched `import Caelestia` →
`import Symmetria` so they'd use the installed plugin. This made imports identical. But
we didn't patch `Paths.state`, leaving GOOD commits reading from `~/.local/state/caelestia/`
(non-existent → zero notifications) and BAD commits reading from `~/.local/state/symmetria/`
(6,890 notifications). The test was fundamentally unfair.

**Lesson:** When normalizing test environments, ensure ALL runtime-significant paths are
equivalent, not just the imports you're focused on.

### Mistake 5: Anchoring on the First Hypothesis

**What happened:** Once we believed "it's the C++ plugin," every subsequent observation
was interpreted through that lens. The perf data showing `ArrayData::realloc()` was
attributed to "plugin initialization" rather than "notification array growth." The binding
statistics were analyzed for plugin cost, not data loading cost.

**Lesson:** When evidence doesn't add up (1.26x more bindings but 38x slower), treat
that as a signal that the hypothesis is wrong, not that the multiplier is explained by
some hidden factor.

---

## QML Performance Rules

These rules emerged from the investigation. They apply to any QuickShell/QML project.

### Rule 1: Never Mutate List Properties in Loops

```qml
// BAD — O(n²) when computed properties bind to myList
for (const item of data)
    root.myList.push(createItem(item));

// GOOD — O(n), single binding evaluation
const temp = [];
for (const item of data)
    temp.push(createItem(item));
root.myList = temp;
```

This applies to `push()`, `splice()`, `unshift()`, and any other mutation. Every mutation
triggers every binding that reads the list. With `n` mutations and `m` bindings, the cost
is `O(n × m × listSize)`.

**Where this pattern exists in Symmetria:** Check any service that loads persisted data
into a list property — clipboard history, app database, calculator history.

### Rule 2: Watch for Hidden Binding Chains

```qml
property list<Item> items: []
readonly property int count: items.length          // re-evaluates on every items change
readonly property bool hasItems: count > 0         // re-evaluates on every count change
readonly property string label: hasItems ? "..." : "empty"  // re-evaluates on every hasItems change
```

Each mutation to `items` cascades through `count` → `hasItems` → `label`. Three binding
evaluations per push. With filter expressions (`.filter()`, `.some()`, `.map()`), each
evaluation is O(n), making the cascade O(n) per mutation.

### Rule 3: Data-Dependent Bugs Need Data-Dependent Tests

A service that works fine with 100 items might freeze with 10,000. Performance testing
should include realistic data volumes, not just fresh-install state.

### Rule 4: Profile Before Optimizing Architecture

We spent a full session trying to defer panel loading (Loader wrapping, setSource,
dynamic components) before profiling showed the panels weren't the bottleneck. A simple
`QML_SHOW_UNIT_STATS=1` run or `perf record` session would have redirected the
investigation much earlier.

---

## Startup Performance Monitoring

### Quick Health Check

Add to a test script or run manually after significant changes:

```bash
#!/bin/bash
# startup-benchmark.sh — Quick startup performance check
# Usage: ./startup-benchmark.sh [runs]
RUNS=${1:-3}
echo "Benchmarking Symmetria startup ($RUNS runs)..."

pkill qs 2>/dev/null; sleep 2

for i in $(seq 1 $RUNS); do
    rm -rf ~/.cache/quickshell/qmlcache
    qs -c symmetria > /tmp/startup-bench-$i.log 2>&1 &
    PID=$!
    for t in $(seq 1 120); do
        if grep -q "BOOT:HB. #1" /tmp/startup-bench-$i.log 2>/dev/null; then break; fi
        sleep 0.5
    done
    T0=$(grep -oP 'ShellRoot @ \K\d+' /tmp/startup-bench-$i.log)
    T1=$(grep -oP 'HB. #1 @ \K\d+' /tmp/startup-bench-$i.log)
    if [ -n "$T0" ] && [ -n "$T1" ]; then
        echo "  Run $i: $(( T1 - T0 ))ms"
    else
        echo "  Run $i: FAILED (no heartbeat)"
    fi
    kill $PID 2>/dev/null; wait $PID 2>/dev/null; sleep 2
done
```

**NOTE:** Requires the heartbeat profiler in shell.qml. Consider keeping it behind a
`--benchmark` flag or environment variable for on-demand use.

### What to Monitor

| Metric | Healthy | Warning | Critical |
|--------|---------|---------|----------|
| Startup freeze | <1s | 1-3s | >5s |
| Notification count | <1000 | 1000-5000 | >5000 |
| State file sizes | <500KB total | 500KB-2MB | >2MB |

### Periodic Checks

```bash
# Notification count
python3 -c "import json; d=json.load(open('$HOME/.local/state/symmetria/notifs.json')); print(f'Notifications: {len(d)}')" 2>/dev/null || echo "Notifications: 0"

# State directory size
du -sh ~/.local/state/symmetria/ 2>/dev/null
```

Consider adding a notification cap (e.g., keep only the most recent 1,000) to prevent
unbounded growth. The current implementation keeps all notifications forever.

---

## Files Modified During Investigation

### Kept (on main)
- `services/Notifs.qml` — batch assignment fix (the actual fix)
- `services/SttService.qml` — error toast for STT failures
- `modules/drawers/Panels.qml` — dashboard module removed (dead code)
- `modules/drawers/Backgrounds.qml` — dashboard background removed
- `modules/drawers/Drawers.qml` — dashboard references removed
- `shell.qml` — heartbeat profiler removed (investigation complete)
- `CLAUDE.md` — process management documentation

### Investigation Docs (kept for reference)
- `docs/startup-delay-investigation/08-deferred-loading-attempts.md`
- `docs/startup-delay-investigation/09-profiling-tools-reference.md`
- `docs/startup-delay-investigation/10-root-cause-bisection.md`
- `docs/startup-delay-investigation/11-postmortem-and-learnings.md` (this file)

### Reverted / Not Kept
- Deferred panels plan (`docs/deferred-panels-plan.md`) — kept as reference but approach abandoned
- sourceComponent wrapping in Panels.qml — zero effect, reverted
- setSource approach — broke sibling types, reverted
- Bar popouts Wrapper deferred loading — zero effect, reverted
- Architecture rewrite plan (`docs/architecture-rewrite-plan.md`) — not needed for startup fix

---

## Future Considerations

### Notification Cap
The current system keeps all notifications forever. Adding a cap (e.g., 1,000 most recent)
would prevent the O(n²) bug from ever mattering again, even if the batch fix were reverted.

### Startup Profiler Flag
Consider a `SYMMETRIA_PROFILE_STARTUP=1` environment variable that enables the heartbeat
profiler, so performance can be checked on-demand without code changes.

### Audit Other List-Loading Services
Check these for the same push-in-loop pattern:
- Clipboard history loading
- Calculator history loading
- App database loading (AppDB via C++ plugin)
- Any future persisted-list service
