# STT Drawer Animation: Show Stutter Fix

## Problem

After the pipeline chaining refactor (`c68b79f`), the STT drawer's show animation broke.
Instead of smoothly sliding down from behind the top bar, the drawer would "peek" at ~25px
(showing just the bottom button row), hold for ~250ms, then snap to full height (~173px)
in a single frame. The hide animation (slide up) worked perfectly.

## Root Cause

Three issues compounded to create the stutter:

### 1. SttService job state timing

`_createJob()` added the job to `_jobs` (triggering the Repeater to create delegates)
while `job._state` was still `"idle"`. The state was only set to `"recording"` after
`_createJob()` returned. Content's FadeTransitions depend on
`serviceState === "recording"`, so they started hidden → `implicitHeight` = 27px.

```
BEFORE:  _createJob() → _jobs=[job,...] → job._state="recording"
                         ↑ Repeater creates delegate here (state = "idle")

AFTER:   _createJob() → job._state="recording" → _jobs=[job,...]
                                                   ↑ Repeater creates delegate here (state = "recording")
```

### 2. Content's internal `Behavior on implicitHeight`

Content.qml has a `Behavior on implicitHeight { Anim {} }` on its container element
(line ~519). This exists to smooth height transitions during state changes
(recording → processing → success). But during the initial show, it animated
Content's height from 27px to 173px over ~400ms — competing with Wrapper's clip
animation that was trying to use 27px as its target.

### 3. QML polish lifecycle: `Component.onCompleted` fires before layout

The original code captured `contentHeight` in `Component.onCompleted`. But in QML's
rendering pipeline:

```
[1] Event processing  ← Component.onCompleted, Qt.callLater(), Timer(0ms)
[2] Polish            ← ColumnLayout computes implicitHeight HERE
[3] Sync
[4] Render
```

`onCompleted` fires in step [1], before ColumnLayout has computed heights in step [2].
The captured `implicitHeight` was always stale. The only reliable hook for reading
layout-dependent sizes is `onImplicitHeightChanged`, which fires AFTER polish.

### Combined effect

```
t=0ms    Repeater creates delegate; job.state = "idle"
         Content.implicitHeight = 27 (FadeTransitions hidden)
         Component.onCompleted captures contentHeight = 27
         showAnim starts: delegate 0 → 27

t=1ms    job._state = "recording" (set after _createJob returns)
         FadeTransitions become visible
         Content's Behavior on implicitHeight starts animating 27 → 173

t=500ms  showAnim completes at 27; ScriptAction binds to live height
         Content's Behavior is at ~120px (still animating)
         delegate SNAPS from 27 to ~120, then tracks remaining growth
         → visible stutter
```

## Solution

Three-layer fix addressing each root cause:

| Layer | File | Change |
|-------|------|--------|
| State timing | `services/SttService.qml` | Move `_jobs` assignment to AFTER `job._state = "recording"` |
| Height behavior | `modules/stt/Content.qml` | Add `enableHeightTransition` prop; Behavior disabled by default |
| Height capture | `modules/stt/Wrapper.qml` | Use `onImplicitHeightChanged` instead of `Component.onCompleted` |

### SttService.qml

Moved `_jobs = [job, ..._jobs]` out of `_createJob()` into callers. Each caller adds to
`_jobs` only after setting the appropriate state. The Repeater now sees the correct state
when creating delegates.

### Content.qml

```qml
property bool enableHeightTransition: false  // Wrapper enables after showAnim

Behavior on implicitHeight {
    enabled: root.enableHeightTransition  // disabled on creation
    Anim {}
}
```

Content reports its full height instantly on creation (no internal animation). After
Wrapper's show animation completes, `enableHeightTransition` is set to `true`, enabling
smooth height transitions for later state changes (recording → processing → success).

### Wrapper.qml

```qml
// Reactive capture — fires after ColumnLayout polish
Connections {
    target: jobContent
    function onImplicitHeightChanged(): void {
        if (!jobDelegate.initialShow) return;
        const h = jobContent.implicitHeight;
        if (h > jobDelegate.contentHeight) {
            if (showAnim.running) showAnim.stop();
            jobDelegate.contentHeight = h;  // triggers showAnim.start()
        }
    }
}
```

Belt-and-suspenders: if Content's height grows while showAnim is in-flight (edge case
where state propagation is delayed), the animation stops and restarts from its current
position toward the new target. The visual result is a seamless continuation.

## Key Findings

- **`Component.onCompleted` is unreliable for layout-dependent sizes.** ColumnLayout
  defers `implicitHeight` computation to the polish phase. Use `onImplicitHeightChanged`
  for any code that needs the final computed size.

- **`Qt.callLater()` and `Timer { interval: 0 }` do NOT fire after polish.** Both are
  processed during event handling (step 1), before polish (step 2). A common misconception
  is that these provide a "next frame" delay — they don't for layout purposes.

- **FadeTransition only animates opacity.** It's a simple wrapper: `visible: show`,
  `opacity: show ? 1 : 0`, `Behavior on opacity { Anim {} }`. Height is forwarded from
  children. The `Behavior on implicitHeight` on Content's container was the actual height
  animation source.

- **Model changes trigger Repeater synchronously.** Setting `_jobs = [job, ...]` causes
  the Repeater to create the delegate in the same JS execution context. Any properties
  not yet set on the job will be stale when the delegate's bindings first evaluate.

## Affected Components

| Component | File | Impact |
|-----------|------|--------|
| SttService | `services/SttService.qml` | `_createJob()` no longer adds to `_jobs`; callers do |
| Content | `modules/stt/Content.qml` | New `enableHeightTransition` property |
| Wrapper | `modules/stt/Wrapper.qml` | Reactive height capture via `onImplicitHeightChanged` |
| FadeTransition | `components/FadeTransition.qml` | No change (only animates opacity) |

## Prevention

- **Never capture layout sizes in `Component.onCompleted`.** Use `onImplicitHeightChanged`
  or `onImplicitWidthChanged` for reliable post-polish values.

- **Set model item state BEFORE adding to model arrays.** When a Repeater's model changes,
  delegates are created synchronously. Ensure the item's state is fully configured before
  the Repeater sees it.

- **When a parent clip animation reveals content, disable internal height animations.**
  Two concurrent height animations on the same visual element always fight. The outer
  clip should be the sole reveal mechanism; inner Behaviors should be suppressed during
  the initial show and re-enabled afterward.

## Approaches Tried and Rejected

| Approach | Result | Why it failed |
|----------|--------|---------------|
| Binding loop fix (`width: visible ? implicitWidth : 0`) | Loops gone, stutter remained | Real bug but not the animation cause |
| `Component.onCompleted` capture | Captured 27 (wrong) | Fires before ColumnLayout polish |
| `Qt.callLater()` capture | Captured 27 (wrong) | Also fires before polish |
| `Timer { interval: 0 }` capture | Captured 27 (wrong) | Also fires before polish |
| `Timer { interval: 50 }` settle delay | Captured 27 (wrong) | Content's height animation barely started |
| `SmoothedAnimation` Behavior | No snap, but "peek-and-retract" | Velocity recalculation when target jumped 27→173 |
| Null parent guard on waveform bars | Errors fixed, stutter remained | Real error but unrelated to animation |
