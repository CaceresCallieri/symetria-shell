# QML Pitfalls

Hard-won lessons from past bugs. Each section documents a non-obvious behavior that has caused real issues in this codebase.

## Required Property Shadowing in Delegates

In QML delegates with `pragma ComponentBehavior: Bound`, there are **two syntaxes** for required properties that behave completely differently:

| Syntax | What it does |
|--------|-------------|
| `required property string foo` | Creates a **NEW shadow property** (does NOT modify the component's existing `foo`) |
| `required foo` | Makes the component's **EXISTING** `foo` property required (model injects directly into it) |

**The Problem:**
```qml
// MyComponent.qml has: property string status: ""

Repeater {
    model: myModel
    MyComponent {
        required property string status  // SHADOW — model value goes here
        // MyComponent's own `status` stays "" — isActive: status !== "" is always false
    }
}
```

**The Fix — two options:**
```qml
// Option A: Make the existing property required (no type redeclaration)
MyComponent {
    required status  // Model injects directly into MyComponent.status
}

// Option B: Use a different name + explicit binding
MyComponent {
    required property string statusRole  // Different name
    status: statusRole                   // Explicit bridge to component property
}
```

**Debugging checklist** when a delegate property appears stuck at its default value:
1. Check if the delegate declares `required property <type> <name>` where `<name>` matches an existing component property
2. If so, either remove the type to use `required <name>`, or rename the delegate property and add an explicit binding
3. Clear `~/.cache/quickshell/qmlcache/` after any QML change

**Reference:** `modules/keycaster/Content.qml` uses `required mouseButton` (Option A) correctly.

### Exception: Model-Injected Properties on Generic Delegates

The shadowing rule above applies when the delegate **extends a type that already has the property**. For generic delegates like `Loader`, `Item`, or `Rectangle` that have **no** existing `modelData` property, you **must** use `required property var modelData` to create a real property:

```qml
Repeater {
    model: myModel
    Loader {
        required property var modelData  // CORRECT — creates property for Repeater to populate
        // required modelData             // WRONG  — Loader has no modelData to reuse
        sourceComponent: MyComponent {
            // With ComponentBehavior: Bound, inner Components can only access real
            // properties on their declaration scope, not Repeater context properties.
            // The `required property var` makes it a real, accessible property.
            value: modelData.someField
        }
    }
}
```

**Rule of thumb:** Use `required foo` when the base type already has `foo`. Use `required property var foo` when it doesn't (model-injected roles on generic containers).

**Reference:** `components/WorkspaceAppIcons.qml` uses `required property var modelData` on both Loader and inner ClientAppIcon delegates. Changing to `required modelData` caused a regression (icons disappeared) because neither type has an inherited `modelData` property.

---

## QML Type Naming Collisions

When multiple directory imports export QML types with the same name, **the last import wins**. This causes silent, catastrophic failures.

**The Problem:**
```qml
// In shell.qml:
import "modules/background"    // Has Background.qml (wallpaper display)
import "modules/keycaster"     // Has Background.qml (drawer shape)

Background {}  // Resolves to keycaster's Background, not wallpaper!
```

**Naming Rules for Module Files:**

| File Purpose | Naming Pattern | Example |
|--------------|----------------|---------|
| Root module entry | `Wrapper.qml` (accessed via `import "modules/x" as XModule` → `XModule.Wrapper {}`) | `DrawersModule.Wrapper`, `BarModule.Wrapper` |
| Modules that don't collide (no `Wrapper` needed) | `ModuleName.qml` | `Keycaster.qml`, `Stt.qml` |
| Module-specific backgrounds | `ModuleNameBackground.qml` | `KeycasterBackground.qml` |
| Internal components | `Content.qml`, other names | OK — never imported in shell.qml |

**Note on `Wrapper.qml` conflicts:** Multiple modules now export `Wrapper.qml`. This is safe because all are imported via qualified aliases (`as XModule`), which bypass QML's last-import-wins collision. `check-qml-conflicts.sh` will show these as "warnings" (not "critical") because no unqualified `Wrapper {}` appears in shell.qml.

**When Adding New Modules:**
1. Check shell.qml for all directory imports
2. List all `.qml` files in those directories
3. Ensure your new module's files don't share names with any of them
4. Prefix module-specific components: `{ModuleName}{Component}.qml`
5. Run `./scripts/check-qml-conflicts.sh` (exit code 1 = critical conflicts)

**Service/Module Name Clash (live example):**

`services/Recorder.qml` (screen-recorder singleton) and the audio recorder IPC handler
would collide if the latter were named `Recorder.qml`. To prevent this, the audio
IPC handler is named `RecorderRoot.qml` in `modules/recorder/`. The naming rule:
if a module's root IPC scope would share a name with an existing service singleton,
append `Root` to the module file name.

---

## Transparency Compensation for Out-of-Backgrounds Components

Components outside the unified `Backgrounds` system in `Drawers.qml` will appear **darker than panel backgrounds**.

The drawer system uses a two-layer opacity pipeline:
```
Transparency layer (Item, layer.enabled: true)
├── opacity: Colours.transparency.base (e.g., 0.45)
└── Backgrounds (layer.enabled: true, opacity: generalBackgroundAlpha = 0.5)
    └── ShapePaths at generalBackgroundOpaque (#000000, fully opaque)
```

Panel backgrounds get **two** multiplicative opacity reductions: `0.5 × 0.45 = 0.225` (22.5% black). Components placed outside this container using `Colours.generalBackground` directly get `0.5` (50% black) — more than double.

**The Fix:**
```qml
readonly property real effectiveAlpha: Colours.generalBackgroundAlpha
    * (Colours.transparency.enabled ? Colours.transparency.base : 1)

color: Qt.alpha(Colours.generalBackgroundOpaque, effectiveAlpha)
```

**When this applies:**
- Overlays placed directly in `Drawers.qml` (outside `Backgrounds` / `Panels`)
- Floating dialogs that bypass the unified background system
- Components that intentionally avoid `Panels` (e.g., to skip Region mask iteration)

**Reference:** `modules/keychords/Overlay.qml`

---

## XOR Mask Inversion in Drawers

The drawers window uses `mask: Region` with `Intersection.Xor` for its Wayland input region. **Expanding the mainRect SHRINKS the input region** — this is counterintuitive.

```
finalInputRegion = fullWindowRect XOR (mainRect - panelSubtractions)
```

Since `mainRect` is inside the full window, XOR inverts it:
- **In input region:** everything NOT in mainRect (border, bar) + panel areas (subtracted then restored by XOR)
- **NOT in input region:** mainRect interior minus panels (clicks pass through to desktop)

**Key rules:**
- `mainRect` defines the **non-interactive interior**, not the interactive area
- To ADD to input region → keep OUTSIDE mainRect
- To REMOVE from input region → include IN mainRect
- Panel subtractions RESTORE those areas to the input region

**Current correct code:**
```qml
y: bar.implicitHeight + win.dragMaskPadding  // Bar is OUTSIDE mainRect → receives input
```

**If changed to `y: 0`:** Bar is INSIDE mainRect → XOR removes it → bar loses all input.

---

## Cursor Shadowing by Visible Disabled MouseAreas

`enabled: false` on a MouseArea prevents event delivery but does NOT prevent it from participating in Qt Quick's cursor hit-testing. A `visible: true` MouseArea at the highest z-order will shadow ALL `cursorShape` settings on items below it.

Full-window MouseAreas in overlays need **both** `enabled` and `visible` guards. Overlay components using scale-driven visibility (`visible: scale > 0`) MUST animate to exactly `0.0` when idle.

**Full details:** `docs/cursor-shape-layer-shell.md`

---

## Full-Window MouseAreas in the Drawers Window

Any `MouseArea { anchors.fill: parent }` placed as a sibling of `Interactions` in the StyledWindow sits above it in z-order and intercepts ALL click events. Such MouseAreas MUST be guarded with `enabled: <condition>`.

**Reference:** `modules/keychords/Overlay.qml` guards its dismiss-on-click MouseArea with `enabled: root.shouldShow`.

---

## Rendering at Small Sizes in Layer-Shell

Both QML `Shape` and `Image` with `layer.enabled: true` (FBO/shader pipeline) can fail to render at small sizes (e.g., 14×22px) in Quickshell's Wayland layer-shell context. `Canvas` (CPU-side QPainter) is a reliable alternative.

## Component.onCompleted Fires Before Layout Polish

`Component.onCompleted` fires during **event processing** (phase 1 of the rendering pipeline), BEFORE `ColumnLayout` and other layouts compute `implicitHeight`/`implicitWidth` in the **polish phase** (phase 2). Reading layout-dependent sizes in `onCompleted` returns stale or partial values.

**Also unreliable for layout sizes:** `Qt.callLater()` and `Timer { interval: 0 }` — both fire during event processing, before polish.

**The reliable hook:** `onImplicitHeightChanged` / `onImplicitWidthChanged` — fires after polish updates the property.

```
QML Rendering Pipeline (per frame):
[1] Event processing  ← onCompleted, Qt.callLater(), Timer(0ms)
[2] Polish            ← Layouts compute implicitHeight/implicitWidth
[3] Sync              ← transfer to scene graph
[4] Render            ← draw frame
```

**Related pitfall — model item state timing:** Setting `_array = [newItem, ..._array]` triggers a Repeater to create delegates synchronously. If the item's state isn't fully configured before the array assignment, delegates see stale state. Always set item properties BEFORE adding to model arrays.

→ Full investigation: [`stt-drawer-animation.md`](stt-drawer-animation.md)

## List Property Mutation in Loops — O(n²) Binding Cascade

**Never mutate a QML list property inside a loop** when computed properties bind to it. Each mutation triggers every binding that reads the list.

```qml
// BAD — O(n²): each push triggers notClosed.filter() + popups.filter()
property list<Item> list: []
readonly property list<Item> notClosed: list.filter(n => !n.closed)
readonly property list<Item> popups: list.filter(n => n.popup)

for (const item of data)
    root.list.push(createItem(item));  // 6,890 pushes = 47M filter ops = 23s freeze

// GOOD — O(n): build locally, assign once
const temp = [];
for (const item of data)
    temp.push(createItem(item));
root.list = temp;  // 1 assignment = 2 filter evaluations
```

**Why it's invisible:** The code looks like normal JavaScript. The O(n²) cost comes from QML's reactive system — `push()` fires a change signal, which triggers bindings, which iterate the list. There's no syntax or warning that indicates this.

**Scaling:** With 100 items: +46ms (unnoticeable). With 6,890 items: +23,000ms (catastrophic). The cost is super-linear because each filter runs over a growing list.

**Check for this pattern in:** Any service that loads persisted data into a list property — notifications, clipboard history, calculator history, app databases.

→ Full investigation: [`startup-delay-investigation/11-postmortem-and-learnings.md`](startup-delay-investigation/11-postmortem-and-learnings.md)

---

## Hypr.activeToplevel is null in fresh shell instances

**Symptom:** `Hypr.activeToplevel` returns `null` even though `Hypr.toplevels` contains 20+ windows and `Hypr.focusedMonitor` is valid. Switching workspaces or clicking a window "fixes" it.

**Cause:** `Hypr.qml` wraps the raw toplevel with a Wayland activation guard:
```qml
// services/Hypr.qml
readonly property HyprlandToplevel activeToplevel:
    Hyprland.activeToplevel?.wayland?.activated ? Hyprland.activeToplevel : null
```

Hyprland reports the focused window via IPC immediately, but the Wayland `activated` protocol event arrives separately and may not have been received yet in a fresh shell instance. The guard filters out the toplevel until that event arrives.

**When you need the raw toplevel:** If you only need window identity (address, class, PID) from Hyprland IPC — not Wayland activation state — use the raw `Hyprland.activeToplevel` as a fallback:
```qml
import Quickshell.Hyprland
// ...
const toplevel = Hypr.activeToplevel ?? Hyprland.activeToplevel;
```

**When you need the filtered version:** For UI features that depend on actual Wayland surface activation (cursor shapes, focus rings, input handling), continue using `Hypr.activeToplevel`.

**Prevention:** When accessing `Hypr.activeToplevel`, consider whether your code needs Wayland activation or just Hyprland window identity. Document which one you're using and why.

## Behavior on height Fails with Rapidly-Changing Bindings

`Behavior on height { NumberAnimation { duration: 100 } }` does **not** work when `height` is bound to a property that changes every animation frame (e.g., via `NumberAnimation on animationTime`).

**The Problem:** Each frame, the binding produces a new value. The `Behavior` cancels its in-progress animation and starts a fresh 100ms animation from the current interpolated value to the new target. With ~16ms between frames, the animation barely progresses before being cancelled — the net visible movement per frame is near-zero and bars appear frozen.

**Also wrong:** `onTargetHeightChanged` with imperative lerp (`smoothed += (target - smoothed) * factor`). This only fires when new data arrives (~10Hz for audio level), leaving ~90ms static gaps between updates. Bars snap instead of gliding.

**Correct approach:** `FrameAnimation` with continuous lerp:
```qml
// Inside a Repeater delegate (id: bar) inside the AudioWaveform component
property real smoothedHeight: targetHeight
FrameAnimation {
    running: root.active
    onTriggered: {
        const delta = bar.targetHeight - bar.smoothedHeight;
        if (Math.abs(delta) > 0.1)
            bar.smoothedHeight += delta * 0.25;
        else
            bar.smoothedHeight = bar.targetHeight;
    }
}
height: smoothedHeight
```

This runs at render framerate, interpolating between sparse data points and naturally tracking rapidly-changing computed targets.

**Prevention:** Never use `Behavior on height` when the bound property changes every frame. Use `FrameAnimation` for continuous value tracking.

## Layer-shell focus restoration race

When a layer-shell window holds `WlrKeyboardFocus.Exclusive` and is unmapped (e.g., `visible: false` or `active = false`), wlroots **atomically restores keyboard focus to whichever window held it before the layer mapped**. This restoration is part of the protocol cleanup, not a request — it cannot be intercepted.

**The trap:** if you dispatch `focuswindow` (or any focus-changing Hyprland command) *synchronously* with the unmap, both events land in Hyprland's queue but the unmap's restoration wins. The user sees focus snap back to the pre-overlay window instead of your chosen target.

**Wrong (focus dispatch loses to restoration):**
```qml
function activate(addr) {
    Hypr.dispatch(`focuswindow address:${addr}`);
    hide();  // unmaps the layer-shell — wlroots restores prior focus AFTER our dispatch
}
```

**Correct (defer dispatch one event-loop tick):**
```qml
function activate(addr) {
    hide();                                                       // unmap first
    Qt.callLater(() => Hypr.dispatch(`focuswindow address:${addr}`));  // dispatch after restoration
}
```

`Qt.callLater` pushes the dispatch to the next event-loop tick, by which point the unmap has propagated through Wayland and wlroots has performed its focus restoration. Our `focuswindow` then lands cleanly on top.

**Why `KillConfirmOverlay` doesn't have this bug:** `killwindow` is destructive — the target dies, so post-unmap focus restoration to some other window is irrelevant (no "wrong focus" outcome exists). Only non-destructive focus actions (`focuswindow`, `movetoworkspace`, etc.) hit this race.

**Diagnosis hint:** if you log the dispatch and verify the same `hyprctl dispatch` works from the CLI, but the QML version "does nothing", suspect this race.

Found in: `services/WindowOverviewService.qml:activateAddr()` for the Window Overview feature.

## ScreencopyView captures off-screen surfaces as empty buffers

`ScreencopyView` captures from a wayland surface's most recently committed buffer. **A surface that is currently off-screen has no recent commit, so the capture is empty (black).** This happens systematically with Hyprland's scrolling layout — windows past the viewport edge stop painting until they're scrolled back into view.

There is **no client-side fix.** Only the compositor can force off-screen surfaces to render. That is precisely how compositor-internal exposé tools (`hyprexpo`, KWin Present Windows) work — they trigger renders from inside the compositor's render loop. As an external Quickshell client we have no equivalent capability.

**Do not spend time trying:**
- Toggling `live: true` momentarily — the surface still doesn't paint when off-screen
- Calling `Hyprland.refreshToplevels()` — only refreshes IPC state, has no effect on rendering
- Repositioning the off-screen window briefly — visible to the user, brittle, breaks scrolling state

**The right fix:** show a fallback view (app icon + class name + title) so the tile is always identifiable even without a thumbnail. See `modules/windowoverview/Tile.qml` for the reference implementation.

Found in: Window Overview tiles for windows scrolled off the visible viewport.

## Property Contract Drift Across Container/Item Boundaries

When a child component exposes a height-like property that a parent container sums or reads to size itself, that property has a **contract**: it must report the child's actual rendered external dimensions. Changing what the property represents (e.g. excluding margins to "simplify" the math inside the child) silently breaks every parent that depends on the previous semantics.

**The notification stack incident** (Notification.qml ↔ Content.qml):

`Notification.qml` exposed `nonAnimHeight` as "the height the card will animate to, including margins." `modules/notifications/Content.qml` sums `nonAnimHeight` across visible cards inside a `ClippingWrapperRectangle` to set the overlay stack's `implicitHeight`. A reasonable-looking refactor split the height calculation:

```qml
// Refactor — looks cleaner, breaks the contract:
readonly property int nonAnimHeight: Math.max(textContent, iconSize)  // content only
implicitHeight: inner.implicitHeight + inner.anchors.margins * 2       // margins added externally
```

The card still rendered at the correct height. But `Content.qml`'s summation now under-allocated by `margins*2` per card. The clipping rectangle cropped the bottom card's body — symptom looked like "the older card is cut off; new cards arrive fine" because re-flowing the list when a new notification arrived briefly re-fired the height bindings, masking the bug on the freshest delegate.

**Why this is hard to catch:**

1. The child component renders correctly in isolation — `implicitHeight` is right.
2. The bug only shows up when the property is *consumed* by a parent that sums it.
3. The symptom (intermittent clipping of older cards) suggests a timing or animation issue, not a property-contract issue.
4. QML's late binding hides the divergence: `notif.implicitHeight` and `notif.nonAnimHeight` returning different values is legal QML; there's no compile-time signal that they were supposed to match.

**The fix pattern:** when a property is part of an external contract, *name it for what consumers need*, and derive the internal pieces from it (or expose both with explicit names). The corrected `Notification.qml` keeps two distinct properties:

```qml
readonly property int contentInnerHeight: Math.max(textContent, iconSize)              // internal use
readonly property int nonAnimHeight: contentInnerHeight + inner.anchors.margins * 2    // external contract — Content.qml depends on this
implicitHeight: inner.implicitHeight + inner.anchors.margins * 2  // inner.implicitHeight = contentInnerHeight; this sum MUST equal nonAnimHeight
```

The invariant `root.implicitHeight === nonAnimHeight` is now load-bearing: any change that breaks it re-introduces the stack-clipping bug. The comments at both definitions call this out so future edits don't quietly drift apart.

**Generalizable rule:** if you change *what a property represents* (its semantics), you must audit every reader, not just verify the local component still looks right. Grep the codebase for the property name before refactoring — if any reader is in a different file, the property has a contract and the rename/restructure needs to land everywhere atomically.

Found in: notifications popup stack — bottom card's body clipped when 2+ cards were visible, especially under non-default `appearance.padding.scale`. Compounded by the Symmetria-specific issue that compact padding scales (e.g. 0.6) magnify the per-card under-allocation as a fraction of total card height.

---

## Repeater over a freshly-rebuilt JS array resets ALL delegates every update

A `Repeater` (or any delegate model) whose `model:` is a **plain JavaScript array** cannot diff updates — a JS array is opaque to Qt. Every time you assign a *new* array, Qt performs a **full model reset**: all delegates are destroyed and recreated, even for items that are logically "the same" as before.

This is invisible for static lists, but becomes a real bug when:
1. The backing data is **re-parsed/rebuilt on every update** (so object references are never stable — e.g. `JSON.parse` of a bridge snapshot), AND
2. The delegate holds **animation/visual state** that depends on per-item data, AND
3. Updates arrive **frequently** (so the constant teardown/rebuild is visible).

**Symptom seen in the agent bar:** with multiple agent chips sharing one Repeater, a *busy* sibling (notably an OpenCode agent, which re-emits state on every tool call) caused the *idle* sibling chips to flash their busy sparkle animation. Each emission replaced `AgentService._agents` with freshly-parsed objects → full Repeater reset → idle delegates recreated → their `activityState` bindings briefly resolved through transient/wrong data during the rebuild → busy sparkle on an idle chip. Claude agents didn't trigger it because they emit a clean `Stop→idle` with no churn.

**Why the obvious theories are wrong:**
- It is **not** "stale imperative animation flags." In `AgentChip.qml`, the busy modes (`working`/`thinking`) are gated on `isBusy`, which derives *purely* from `activityState`. The imperative flags (`_isClosing`, `_blinkClosing`, …) can only ever select `stopping`/morph variants — they cannot fabricate a busy animation. So a busy animation on an idle chip means the **`activityState` binding itself resolved to the wrong agent**, i.e. a delegate-identity problem, not a flag problem.
- Stable *ordering* does not save you: the reset happens regardless of whether the array order changed, because Qt never compares contents.

**The fix — give the model a stable identity key.** Wrap the array in Quickshell's `ScriptModel` and set `objectProp` to a property that uniquely and stably identifies each item across rebuilds:

```qml
import Quickshell
// ...
Repeater {
    model: ScriptModel {
        values: root.agents      // freshly-parsed array each emission
        objectProp: "id"         // stable per-agent key ("<nvim_pid>_<buf>")
    }
    AgentChipFor { required property var modelData; agent: modelData }
}
```

With `objectProp`, ScriptModel treats two different object instances sharing the same key value as the **same row**: it updates the existing delegate in place (emitting `dataChanged`) instead of destroying and recreating it. Unchanged siblings are never touched when one item churns. This is the established convention across the bar (`Workspaces`, `StatusIcons`, `Network`, `OccupiedBg`, …) — agent-chip Repeaters were the outliers using plain arrays.

**Rule of thumb:** any `Repeater`/delegate model bound to an array that is *rebuilt* (not mutated in place) on updates should use `ScriptModel { values; objectProp }` keyed on a stable id — especially if the delegate animates. Plain-array models are fine only for build-once / rarely-changing lists.

Found in: agent bar — idle Claude chips animated as "thinking" while an OpenCode sibling worked. Fixed by keying `AgentChipGroup`, `ProjectGroup`, and the orphan-agent Repeater (`MergedBarContent`) on `objectProp: "id"`.

## `readonly property` blocks ALL assignment, including same-file handlers

`readonly` in QML does **not** mean "only this component may write it" — it means the property has **exactly one** value source, its initializer binding, and **no imperative assignment is legal from any scope**, including signal handlers *in the same file*. Assigning to it (`root.foo = …`) throws `Cannot assign to read-only property "foo"` at runtime; the write silently no-ops and the property is frozen at its initializer value.

This is a tempting "encapsulation" change to make during review — a singleton property that should only ever be set by one internal `FileView`/`Process`/`Timer` *looks* like it wants to be `readonly`. But if that internal writer assigns imperatively, `readonly` breaks it.

**Symptom seen in `QuietMode.qml`:** `enabled` was changed to `readonly property bool enabled: false`, with a `FileView.onLoaded` handler doing `root.enabled = /^ENABLED=1\b/m.test(text())`. The handler's assignment threw and no-op'd, so `enabled` was pinned to `false` forever — the Silent power-mode pill never lit up and could not be toggled, even though the underlying `sudo quiet-mode on/off` was working fine. The bug is invisible to `qmllint` (it can't resolve Quickshell imports, exits 255 silently) and only surfaces at runtime.

**Why the reasoning behind the change is wrong:** the assumption is "`readonly` forbids *external* writes but allows the declaring component to mutate it internally." QML has no such distinction — there is no `private`/`internal` write scope. `readonly` is absolute.

**The fix depends on how the value is produced:**
- **Imperatively assigned** (signal handler computes and sets it — e.g. `FileView.onLoaded`): it **must be a plain writable** `property`. Do not mark it `readonly`. Add a comment so a future reviewer doesn't re-apply the "improvement."
- **Genuinely derived** (a pure expression of other reactive properties): then `readonly property bool enabled: <expr>` is correct *and* you never need to assign it. If you want both encapsulation *and* an imperative internal writer, split them: a writable `property bool _enabled` that the handler sets, plus `readonly property bool enabled: _enabled` as the public, unwritable view.

```qml
// WRONG — onLoaded assignment throws, enabled stuck at false:
readonly property bool enabled: false
FileView { onLoaded: root.enabled = parse(text()) }   // Cannot assign to read-only property

// RIGHT — writable, with a regression guard:
property bool enabled: false   // NOT readonly: the FileView below assigns to it
FileView { onLoaded: root.enabled = parse(text()) }
```

Found in: `services/QuietMode.qml` — a `/seal` code review "hardened" `enabled` to `readonly`, which froze it false and broke the Silent toggle. Reverted to writable with an inline regression-guard comment.

### Counter-example: `readonly property list<T>` DOES accept reassignment

The rule above holds for value-typed properties (`bool`, `int`, `string`, object references). It does **not** hold for `list<T>`:

```qml
// This works — the assignment is NOT a no-op:
readonly property list<AccessPoint> networks: []
...
root.networks = updated;   // succeeds, bindings fire
```

`services/NmcliWifi.qml` has done exactly this since the initial import, and the network list demonstrably updates. Qt evidently treats a `readonly` list property's declared value as the initial contents rather than as a frozen binding.

Why this matters: someone applying the `QuietMode` lesson mechanically will read `root.networks = updated` as a latent frozen-value bug and "fix" the `readonly` away — a pointless diff — or, worse, will assume the reverse and mark some *other* imperatively-written property `readonly` because "this one works." Neither inference is safe. **Check the property's type before reasoning about `readonly`:** the freeze applies to value types; lists are the documented exception.

This was surfaced during the 2026-07-27 wifi review, where it was flagged as suspicious-but-working rather than as a defect.

## `parent.radius` is undefined inside a ClippingRectangle

`ClippingRectangle` (Quickshell.Widgets, aliased here as `StyledClippingRect`)
declares its default slot as `default property alias data: contentItem.data`.
Children written inside it are therefore **reparented into `contentItem`** — a
plain `Item` with no `radius`. So this silently breaks:

```qml
StyledClippingRect {
    id: pillBody
    radius: root.radius

    Rectangle {
        anchors.fill: parent
        radius: parent.radius     // ← parent is contentItem, NOT pillBody. undefined.
    }
}
```

The symptom is a flood of `Unable to assign [undefined] to double` warnings —
one per instance per evaluation, so a handful of pills produced ~280 lines at a
single startup. Visually it is usually **invisible**, which is why it survives:
the child gets `radius: 0` (square corners), but the enclosing
ClippingRectangle clips the overflow away anyway. The bug only becomes visible
if the same construct is later moved into a non-clipping container.

**Fix:** bind to the owning component's own property, not to `parent`:

```qml
radius: root.radius
```

This is safe everywhere — it does not depend on what the body type is or on
whether the default slot reparents — so prefer `root.<prop>` over
`parent.<prop>` in these primitives as a rule, not just where it currently
breaks.

Note that `anchors.fill: parent` in the same block is still correct: filling
`contentItem` is exactly the desired geometry. Only the *property read* is wrong.

Found in: `components/PillSurface.qml`, `components/PillToggleSurface.qml`
(pre-existing, since the primitives were written). `components/PillCard.qml`
was unaffected — its body is a plain `StyledRect`, which does not reparent.

## Quickshell drops the SECOND IpcHandler registered for a target

`IpcHandler` targets are global. Registering two handlers with the same
`target:` does not merge their functions — the second one is discarded, with
only a warning at startup:

```
QML IpcHandler at @modules/Shortcuts.qml[246:5]: Handler was registered but
will not be used because another handler is registered for target theme
```

The IPC call then fails, or silently hits the *other* handler's function set,
with nothing at the call site to explain it. Before adding a handler, grep for
the target name:

```bash
grep -rn 'target: "<name>"' --include='*.qml' .
```

Found in: a new `target: "theme"` handler for the surface design language
collided with the palette-dump handler that `services/Colours.qml` has always
registered. Renamed to `target: "surface"`.
