# Investigation: stt-drawer-animation

**Started**: 2026-03-13 01:28
**Status**: Finalized

---

## Pass 1

**Timestamp**: 2026-03-13 01:28
**Status**: narrowing

### Context

After the pipeline chaining refactor (`c68b79f`), the STT drawer's show and hide
animations broke. The refactor changed Wrapper.qml from a Loader-based single-content
approach to a Row + Repeater over SttService.jobs for multi-card support.

### Findings

- **Hide animation fixed**: Per-delegate vertical animation approach works correctly.
  Each delegate has its own `showAnim` (slide down) and `hideAnim` (slide up) via
  SequentialAnimation. The Wrapper is now a passive container tracking Row dimensions.
  User confirmed: "the going up animation is perfect."

- **Show animation still stutters**: The slide-down has a visible stagger/pause at start.
  User: "it's like it's staggered as soon as it is starting... the animation is not
  completely uniform."

- **Binding loop at Content.qml:538,547**: Two StyledText elements have
  `width: visible ? implicitWidth : 0` which creates a self-referential binding loop.
  QML Text's `implicitWidth` can depend on `width` (text wrapping), creating a cycle.
  ```
  WARN scene: QML StyledText at @modules/stt/Content.qml[538:25]: Binding loop detected for property "width"
  WARN scene: QML StyledText at @modules/stt/Content.qml[547:25]: Binding loop detected for property "width"
  ```
  These fire during STT start. The unstable width could cascade to Content's
  `implicitHeight`, causing `contentHeight` snapshot to capture wrong value.

- **Null parent error at Content.qml:659**: Waveform bar `y: (parent.height - height) / 2`
  fires 20 errors (one per bar) because `parent` is null during Repeater delegate
  construction. **Fixed** with null guard `parent ? ... : 0` but stutter persisted.
  ```
  WARN scene: @modules/stt/Content.qml[659:29]: TypeError: Cannot read property 'height' of null
  ```

- **Original pre-refactor approach** (commit `343c15e`): Used a Loader with a preload phase:
  1. Shell startup → `Component.onCompleted` → `timer.startPreload()`
  2. Loader creates Content invisibly (`active=true, visible=false`)
  3. Content has stable dimensions (binds to SttService singleton properties)
  4. Content's `Component.onCompleted: root.contentHeight = implicitHeight` captures height
  5. Timer (1000ms) fires → `finalize()` re-captures height, restores visibility
  6. **`contentHeight` was already known BEFORE any recording started**
  7. Recording starts → `shouldBeActive=true` → `showAnim.start()` with stable target

- **Current approach**: Content created by Repeater at exactly the moment animation
  needs to start. No preload gap. `contentHeight` captured in Content's
  `Component.onCompleted` but at that point layout may not be settled yet.

### Hypotheses

| # | Hypothesis | Confidence | Evidence |
|---|-----------|------------|----------|
| 1 | Binding loops at Content.qml:538,547 cause unstable `implicitHeight` during initial layout, making `contentHeight` snapshot wrong | HIGH | Binding loops fire during start; `width: visible ? implicitWidth : 0` is self-referential in Text elements |
| 2 | Content.onCompleted fires before full layout settles, capturing wrong `contentHeight` | MED | Original code had 1000ms preload delay; we have no delay at all |
| 3 | Multiple layout passes cause `implicitHeight` to change after `contentHeight` is captured | MED | Complex component with dynamic state-dependent layout |

### Eliminated

- **Live binding target (`to: jobContent.implicitHeight`)**: Replaced with stable
  `contentHeight` snapshot. Stutter persisted → not the sole cause, though it was
  also a real problem.
- **Wrapper-level show/hide animation with Repeater model**: Completely replaced
  with per-delegate animations. Hide works perfectly, show still stutters.
- **Null parent on waveform bars**: Fixed with null guard. Stutter persisted →
  not the cause (but was a real error that needed fixing).
- **`closingLastJob` signal approach**: Removed in favor of per-delegate hide
  animations which work correctly.
- **heightWatcher Connections approach**: Removed in favor of per-delegate
  `contentHeight` snapshot pattern.

### Code Paths

| File | Lines | Role |
|------|-------|------|
| `modules/stt/Wrapper.qml` | full | Per-delegate animation wrapper (current, 119 lines) |
| `modules/stt/Content.qml` | 538, 547 | Binding loop source: `width: visible ? implicitWidth : 0` |
| `modules/stt/Content.qml` | 659 | Fixed null parent: `y: parent ? (parent.height - height) / 2 : 0` |
| `modules/stt/Content.qml` | 565-667 | FadeTransition + Row + Repeater waveform bars |
| `services/SttService.qml` | 292-295 | `_removeJob()`: sets `closing=true` + starts `_removalTimer` |
| `services/SttService.qml` | 852-855 | `_removalTimer`: 450ms interval (Appearance.anim.durations.normal + 50) |
| `git show 343c15e:modules/stt/Wrapper.qml` | full | Original pre-refactor Wrapper with Loader + preload |

### Current Wrapper Architecture (per-delegate)

```
Wrapper (passive: implicitHeight = jobsRow.implicitHeight)
 └── Row (anchors.bottom, horizontalCenter)
      └── Repeater (ScriptModel: SttService.jobs)
           └── delegate Item (own showAnim↓ / hideAnim↑)
                ├── contentHeight: snapshot (set in Content.onCompleted)
                ├── showAnim: 0 → contentHeight, then bind to live
                ├── hideAnim: break binding, animate to 0
                ├── onClosingChanged → hideAnim.start()
                └── Content (anchors.bottom: parent.bottom)
```

### Errors & Symptoms

```
WARN scene: QML StyledText at @modules/stt/Content.qml[538:25]: Binding loop detected for property "width"
WARN scene: QML StyledText at @modules/stt/Content.qml[547:25]: Binding loop detected for property "width"
```
Reproduction: `qs ipc -c symmetria call stt start en`

Visual: Show animation has visible stutter/pause at start. Not smooth like hide.

### Next Steps

- [ ] **Fix binding loops at Content.qml:538,547**: Replace `width: visible ? implicitWidth : 0`
  with a non-circular pattern. Options:
  - Wrap each StyledText in an Item that manages width without self-reference
  - Remove explicit `width` and use `visible` alone (if Row handles spacing correctly)
  - Use `Layout.preferredWidth` if inside a Layout
- [ ] **After fixing loops, test if stutter resolves**: The binding loops likely cause
  Content's `implicitHeight` to be unstable during initial layout, making the
  `contentHeight` snapshot capture wrong and the animation target incorrect.
- [ ] **If stutter persists after binding loop fix**: Consider adding a 1-frame delay
  (Timer interval: 0) between Content creation and `contentHeight` capture, similar
  to original preload concept but per-delegate. Or use `Qt.callLater()` to defer
  capture until after layout polish.

### Open Questions

- Were these binding loops present before the refactor? The Content component code
  (lines 538, 547) wasn't changed in the refactor, but the instantiation context
  changed (Loader → direct Repeater child). Binding loops may be context-sensitive.
- Does the original Askpass Wrapper also have a preload delay for the same reason?
  (Yes — 1000ms timer, confirming that immediate measurement is unreliable.)

---

## Pass 2

**Timestamp**: 2026-03-13 03:00
**Status**: root-cause-identified

### Context

Continuing from Pass 1.  Binding loops fixed, then instrumented Wrapper.qml with
detailed logging to trace the exact animation lifecycle frame-by-frame.

### Findings

- **Binding loops fixed (Content.qml:538,547)**: Removed `width: visible ? implicitWidth : 0`
  from two StyledText elements.  `Row` parent already skips invisible children.  No more
  binding loop warnings.  **Did not fix the stutter.**

- **Root cause confirmed by logging — TWO concurrent animations fighting**:
  Content has an internal `FadeTransition` at line ~529 that animates the waveform section
  into view when `serviceState === "recording"`.  This grows Content.implicitHeight from
  **27px** (info bar only) to **173px** (info bar + waveform) over **~60 frames (~1000ms)**.
  The show animation captures `contentHeight=27` and animates delegate 0→27 over 500ms.
  When showAnim finishes, `ScriptAction` binds to live height → **instant snap 27→173**.

  Timeline from logs:
  ```
  t=0ms   Content.onCompleted: implicitHeight=27
  t=50ms  settleTimer fires: content.implicitHeight=27 (FadeTransition barely started)
  t=0-500ms  showAnim: delegate 0→27 (correct animation, wrong target)
  t=0-1000ms Content FadeTransition: implicitHeight 27→173 (concurrent, independent)
  t=500ms showAnim done → bind to live → SNAP delegate 27→173
  ```

- **FadeTransition duration is ~1000ms**: Content.implicitHeight progression from logs:
  27 → 27.3 → 28.3 → 30.3 → 33.4 → 38.2 → 44.6 → 52.6 → 61.4 → 70.1 → 78.2 →
  85.6 → 93.2 → 99.1 → 104.4 → 109.2 → 113.6 → 117.6 → 121.3 → 124.8 → 128.0 →
  ... → 172.9 → 173.0
  This is a smooth easing curve over ~60 frames at 60fps = ~1000ms.

- **50ms settle delay insufficient**: Timer fires while Content is still at 27px.
  Content's FadeTransition hasn't meaningfully progressed at 50ms.  Would need
  **≥1000ms** delay to capture stable height — unacceptable for UX.

- **SmoothedAnimation approach**: Replaced NumberAnimation with `SmoothedAnimation`
  `Behavior` that tracks Content.implicitHeight live.  The snap was eliminated —
  delegate smoothly chased from 0 to 173.  BUT the SmoothedAnimation restart when
  target jumped from 27→173 caused a visible velocity dip / perceptual "peek and
  retract" effect.  User: "it appears a little bit, goes back, and then appears
  completely."  Interestingly, with the SmoothedAnimation binding, Content.implicitHeight
  jumped to 173 within 2 frames instead of 60 — suggesting the live binding feedback
  short-circuits the FadeTransition.

### Hypotheses

| # | Hypothesis | Confidence | Evidence |
|---|-----------|------------|----------|
| 1 | Content's internal FadeTransition must be bypassed/disabled during initial show — the Wrapper clip animation IS the reveal, making FadeTransition redundant and harmful | HIGH | Two concurrent height animations always fight; original preload avoided this by completing FadeTransition before showAnim started |
| 2 | Alternatively, delay showAnim until FadeTransition completes (~1000ms) — but this is unacceptable UX | LOW | Would need 1000ms delay before drawer appears |
| 3 | Capture the FadeTransition's FINAL height upfront by briefly forcing Content to its fully-expanded state, measuring, then reverting | MED | Complex but avoids modifying Content.qml |

### Eliminated

- **Binding loops at Content.qml:538,547**: Fixed (removed `width: visible ? implicitWidth : 0`).
  Did NOT fix the stutter.  The loops were a real bug but not the cause.
- **`Qt.callLater()` deferred capture**: Still captures 27 — FadeTransition hasn't started.
- **50ms Timer settle delay**: Content still at 27px after 50ms.  FadeTransition takes ~1000ms.
- **SmoothedAnimation Behavior**: Eliminates the snap but introduces a perceptual
  "peek-and-retract" artifact from velocity recalculation when target jumps 27→173.
  User rejected: "appears a little bit, goes back, then appears completely."
- **Content.onCompleted + Qt.callLater capture**: Both fire before FadeTransition starts.

### Code Paths

| File | Lines | Role |
|------|-------|------|
| `modules/stt/Wrapper.qml` | full | Per-delegate animation wrapper (current state has Timer + NumberAnimation + logging) |
| `modules/stt/Content.qml` | 536-538, 545-547 | Fixed: removed `width: visible ? implicitWidth : 0` |
| `modules/stt/Content.qml` | ~529 | FadeTransition wrapping waveform section (`show: serviceState === "recording"`) |
| `modules/stt/Content.qml` | 565-667 | Waveform bars Row + Repeater inside FadeTransition |
| `components/FadeTransition.qml` | unknown | Need to read — controls Content height growth |

### Key Data

**Content.implicitHeight progression** (FadeTransition, ~1000ms):
```
Frame   Height    Delta
0       27.0      —        (info bar only)
1       27.3      +0.3
2       28.3      +1.0
3       30.3      +2.0
4       33.4      +3.1
5       38.2      +4.8     (accelerating)
...
30      145.1     +2.0     (decelerating)
...
60      173.0     +0.1     (final — info + waveform)
```

### Next Steps

- [ ] **Read `components/FadeTransition.qml`**: Understand how it animates and whether
  it can be bypassed.  Key questions: Does it use `height`? `opacity`? `clip`?
  Can its animation be skipped when Content is first created?
- [ ] **Option A — Suppress FadeTransition on initial show**: Add a property like
  `skipInitialTransition` to Content.  On first creation, FadeTransition starts in
  its final state (full height), so contentHeight snapshot = 173.  The Wrapper clip
  animation handles the reveal.  FadeTransition still runs for later state changes
  (recording → processing → error).
- [ ] **Option B — Use FadeTransition's final height directly**: If FadeTransition
  exposes a `targetHeight` or its children have known dimensions, compute 173
  without waiting for the animation.
- [ ] **Option C — SmoothedAnimation with tuned parameters**: The SmoothedAnimation
  approach almost worked.  If the velocity dip on restart can be eliminated (e.g.,
  by using `reverseMode: SmoothedAnimation.Immediate` or `maximumEasingTime: 0`),
  the "peek-and-retract" might disappear.
- [ ] **Remove debug logging** from Wrapper.qml after fix is confirmed.

### Open Questions

- What does FadeTransition actually animate?  `height`, `opacity`, `scale`, `clip`?
- Can FadeTransition be started in its "shown" state without running the animation?
- With SmoothedAnimation, Content.implicitHeight jumped to 173 in 2 frames (vs 60
  frames with NumberAnimation).  Why?  Does the live binding between delegate and
  Content height somehow short-circuit the FadeTransition?  If so, could we
  exploit this — bind briefly to get 173, capture it, unbind, then animate?

---

## Pass 3

**Timestamp**: 2026-03-13 14:00
**Status**: resolved

### Context

Pass 2 identified the root cause as two concurrent animations fighting.  Video analysis
(via animation-video-analyzer) confirmed: a ~25px "peek" holds for ~250ms, then snaps to
full height.  Web research into QML's rendering pipeline revealed a deeper timing issue:
`Component.onCompleted`, `Qt.callLater()`, and `Timer { interval: 0 }` ALL fire during
event processing — BEFORE the polish phase where ColumnLayout computes `implicitHeight`.

### Findings

- **FadeTransition only animates opacity, not height**: `FadeTransition.qml` is minimal —
  `visible: show`, `opacity: show ? 1 : 0`, `Behavior on opacity { Anim {} }`, forwards
  `implicitHeight` from first child.  The gradual 27→173 height growth is NOT from
  FadeTransition itself.

- **True height animation source: `Behavior on implicitHeight` at Content.qml:519**:
  Content's container StyledRect has `Behavior on implicitHeight { Anim {} }` which
  animates `container.implicitHeight = ColumnLayout.implicitHeight + padding`.  When
  FadeTransitions become visible (ColumnLayout grows), this Behavior smooths the change
  over `Appearance.anim.durations.normal` (~400ms).  This was the "~1000ms" growth
  observed in Pass 2 (easing curve tail).

- **SttService timing bug**: `_createJob()` adds the job to `_jobs` (triggering Repeater
  delegate creation) while `job._state` is still `"idle"`.  State is only set to
  `"recording"` AFTER `_createJob` returns (line 168).  So Content's FadeTransitions
  start with `show: false` → `implicitHeight` = 27.

- **QML rendering pipeline lifecycle**:
  ```
  [1] Event processing: timers, signals, Qt.callLater, Component.onCompleted
  [2] Polish: ColumnLayout computes implicitHeight
  [3] Sync: transfer to scene graph
  [4] Render: draw frame
  ```
  `onCompleted` fires in step [1].  ColumnLayout heights update in step [2].
  `onImplicitHeightChanged` fires AFTER step [2].  This is the ONLY reliable hook
  for reading layout-dependent sizes.

### Solution (3-layer fix)

1. **SttService.qml** — Moved `_jobs = [job, ..._jobs]` out of `_createJob()` and into
   callers, AFTER setting the job state.  In `start()`, the assignment now happens after
   `job._state = "recording"`.  Repeater delegates see the correct state from creation.

2. **Content.qml** — Added `property bool enableHeightTransition: false` (default off).
   The `Behavior on implicitHeight` checks `enabled: root.enableHeightTransition`.
   Content reports its full height instantly on creation (no internal animation).

3. **Wrapper.qml** — Replaced `Component.onCompleted` capture with `onImplicitHeightChanged`
   handler on Content.  This fires after ColumnLayout polish with the correct height.
   Added `initialShow` guard + restart logic: if Content's height grows mid-animation
   (belt-and-suspenders for timing edge cases), showAnim stops and restarts from its
   current position.  After showAnim completes, `enableHeightTransition = true` re-enables
   Content's internal height transitions for future state changes.

### Eliminated (cumulative from all passes)

- **Binding loops at Content.qml:538,547**: Fixed but not the stutter cause
- **Null parent on waveform bars**: Fixed but not the stutter cause
- **Live binding target**: Replaced with snapshot — stutter persisted
- **Qt.callLater() / Timer(0ms) deferred capture**: Both fire before polish
- **50ms settle Timer**: Content still at 27px (FadeTransition barely started)
- **SmoothedAnimation Behavior**: Eliminated snap but created peek-and-retract
- **Component.onCompleted capture**: Fires before ColumnLayout polish phase
