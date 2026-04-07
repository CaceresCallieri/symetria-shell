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
