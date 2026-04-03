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
| Root module entry | `ModuleName.qml` | `Keycaster.qml` |
| Module-specific backgrounds | `ModuleNameBackground.qml` | `KeycasterBackground.qml` |
| Internal components | `Wrapper.qml`, `Content.qml` | OK — not imported in shell.qml |

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
