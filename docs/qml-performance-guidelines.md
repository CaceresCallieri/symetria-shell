# QML / Qt Quick Performance Guidelines

Actionable rules for a Qt 6.11+ / QuickShell-based Wayland compositor shell. Each item is a concrete pattern to prefer or avoid, with a severity rating for the anti-pattern it addresses.

---

## 1. QML List / Model Performance

### 1.1 Never mutate a QML list property inside a loop
**Severity: CRITICAL**

Each `push()` to a QML `list<>` property fires a change signal. Every binding that reads the list (`.filter()`, `.map()`, `.length`) re-evaluates on every push. With N items and M bindings, cost is O(N*M*N).

```qml
// BAD — O(n^2): each push triggers all downstream bindings
for (const item of data)
    root.list.push(createItem(item));

// GOOD — O(n): build locally, assign once
const temp = [];
for (const item of data)
    temp.push(createItem(item));
root.list = temp;  // single change signal, single evaluation per binding
```

### 1.2 Use QAbstractItemModel for datasets over ~100 items
**Severity: HIGH**

QML `ListModel` is 4-6x slower with dynamic roles and lacks fine-grained `dataChanged` signals. C++ models emit `dataChanged` with a role vector, so QML only re-evaluates the specific role bindings that changed. QML ListModel is acceptable for prototyping and small static collections only.

### 1.3 Never enable ListModel.dynamicRoles
**Severity: HIGH**

`dynamicRoles: true` disables internal type optimizations. Qt docs say it causes "much worse" performance. Keep role types stable per element.

### 1.4 Prefer ListView over Repeater for scrollable content
**Severity: MEDIUM**

Repeater instantiates ALL delegates immediately. ListView only creates delegates visible in the viewport (plus `cacheBuffer`). Use `Repeater` only for small fixed-size collections (fewer than ~20-30 items) that are all visible simultaneously.

Exception: For fixed-length lists that need buttery-smooth scrolling, `Flickable + Column + Repeater` can outperform ListView because it avoids delegate creation/destruction during scroll.

### 1.5 Enable delegate recycling on ListView and TableView
**Severity: HIGH**

```qml
ListView {
    reuseItems: true  // Qt 5.15+ / Qt 6
}
```

Recycled delegates receive `pooled` and `reused` signals. Rules:
- Never store state in delegates; reset on `reused` signal
- Pause timers/animations on `pooled` signal
- Avoid `Component.onCompleted` for state that should refresh on reuse

### 1.6 Emit dataChanged with specific roles
**Severity: MEDIUM**

When implementing `QAbstractItemModel`, pass the changed roles vector in `dataChanged()`. Without it, QML re-evaluates ALL role bindings for the affected rows.

---

## 2. Binding Evaluation Costs

### 2.1 Understand the push notification system
**Severity: CRITICAL (architectural awareness)**

QML uses **push-based** dependency tracking, not pull/dirty-flag. When a captured property changes, its NOTIFY signal immediately triggers re-evaluation of every binding that referenced it. There is no batching -- if three properties change in the same C++ method, dependent bindings evaluate three times. There is no lazy "is-dirty" check.

### 2.2 Bindings on invisible items still evaluate
**Severity: HIGH**

`visible: false` stops rendering but does NOT stop binding evaluation. Hidden tab pages with bindings to frequently-changing properties waste CPU. Use `Loader` with `active: false` to destroy the component tree entirely when not needed.

### 2.3 Avoid cascading binding chains
**Severity: HIGH**

Property A -> Binding B -> Property C -> Binding D creates a cascade where changing A triggers B, which changes C, which triggers D. Each intermediate property change is a separate evaluation pass. Flatten chains where possible.

```qml
// BAD — 3-deep cascade
property real rawValue: slider.value
property real scaledValue: rawValue * 100
property string displayText: scaledValue.toFixed(0) + "%"

// BETTER — single binding with no intermediaries (if intermediaries aren't reused)
property string displayText: (slider.value * 100).toFixed(0) + "%"
```

Only keep intermediate properties when they are referenced by multiple consumers.

### 2.4 Use property aliases instead of binding bridges
**Severity: MEDIUM**

Aliases are direct references, not evaluated expressions. They skip the binding evaluation overhead entirely.

```qml
// SLOWER — creates a binding that monitors root.color
property color bgColor: root.color

// FASTER — direct reference, no evaluation overhead
property alias bgColor: root.color
```

### 2.5 Conditional bindings only track properties from the executed branch
**Severity: LOW (informational)**

`if (a) then b else c` — when `a` is false, only `a` and `c` are captured. Changes to `b` will not trigger re-evaluation until `a` becomes true. This is usually desirable but can surprise when debugging.

### 2.6 Add intermediate bindings to isolate sequence element access
**Severity: MEDIUM**

When binding to a single element of a list/sequence property, any change to ANY element fires the property's change signal. An intermediate property isolates dependents:

```qml
// BAD — re-evaluates whenever ANY element in the list changes
width: myList[3] + 10

// GOOD — intermediate absorbs the spurious notifications
property int cachedElement: myList[3]
width: cachedElement + 10  // only re-evaluates if element 3 actually changed
```

### 2.7 Never imperatively assign to a bound property
**Severity: HIGH**

`root.checked = !root.checked` permanently breaks the binding on `checked`. Use either:
- Method calls (`internal.toggle()`) that modify the backing store without direct property writes
- `Binding` type with `restoreMode` for temporary overrides
- Signal-based "proposed value" pattern for custom controls

Enable `qt.qml.binding.removal` logging category to detect broken bindings.

---

## 3. Component Loading

### 3.1 Use Loader for deferred/conditional content
**Severity: HIGH**

```qml
Loader {
    active: tabBar.currentIndex === 2  // only created when needed
    asynchronous: true                  // spread across frames
    source: "HeavyContent.qml"
    visible: status === Loader.Ready    // hide progressive loading
}
```

Loader overhead is nontrivial -- do not use for tiny items. Reserve for page-level components, dialogs, and complex panels.

### 3.2 First visible content: load synchronously
**Severity: MEDIUM**

The initial screen should load synchronously so the user sees content immediately. Use `asynchronous: true` only for subsequent off-screen or deferred content.

### 3.3 Chain loaders to match CPU core count
**Severity: MEDIUM**

For startup optimization, use N concurrent Loaders (where N ~ CPU cores). The first Loader is synchronous (immediate content); the rest are asynchronous. This parallelizes QML compilation and instantiation.

### 3.4 Component.createObject requires careful ownership management
**Severity: HIGH**

Dynamically created objects default to `JavaScriptOwnership` (GC-collected). Always pass a parent:

```qml
// BAD — orphan, depends on GC for cleanup
var obj = comp.createObject(null, { text: "hello" });

// GOOD — parented, destroyed with parent
var obj = comp.createObject(parentItem, { text: "hello" });
```

Call `obj.destroy()` explicitly when done. Do not rely on GC timing.

### 3.5 Set object state BEFORE adding to model arrays
**Severity: HIGH**

Repeater creates delegates synchronously when a model array changes. If the item's state is not fully configured before the array assignment, delegates see stale/partial state.

```qml
// BAD
root.list = [newItem, ...root.list];
newItem.status = "active";  // too late, delegate already created

// GOOD
newItem.status = "active";
root.list = [newItem, ...root.list];
```

### 3.6 Use AsynchronousIfNested for view delegates
**Severity: LOW**

`QQmlIncubator::AsynchronousIfNested` creates delegates asynchronously if the parent view is itself inside an async instantiation, and synchronously otherwise. This prevents empty-then-populated flicker for top-level views while still spreading load for nested ones.

---

## 4. Memory Management

### 4.1 Never manually invoke gc() during interactive use
**Severity: CRITICAL**

`gc()` blocks the GUI thread for hundreds of milliseconds to over a second. Since Qt 6.8, GC runs incrementally by default (shorter pauses, more frequent). Only call `gc()` during guaranteed idle periods (app minimized, screen locked).

### 4.2 Destroy dynamic objects explicitly
**Severity: HIGH**

Do not rely on JavaScript garbage collection for QObject cleanup. `destroy()` calls `QObject::deleteLater()`, which is deterministic. GC timing is heuristic-based and may delay cleanup indefinitely for objects with few references.

### 4.3 Beware parentless QObjects returned to QML
**Severity: HIGH**

QObjects without a parent that are returned from `Q_INVOKABLE` functions get `JavaScriptOwnership`. When QML loses all references, GC deletes the underlying C++ object. If C++ still holds a pointer, it becomes a dangling reference. Set `CppOwnership` explicitly if C++ retains ownership:

```cpp
QQmlEngine::setObjectOwnership(obj, QQmlEngine::CppOwnership);
```

### 4.4 Consolidate implicit types into reusable components
**Severity: MEDIUM**

Every QML item with custom properties creates a unique implicit type with its own metadata. If multiple places define identical property sets on anonymous items, memory is wasted. Extract into a named component:

```qml
// BAD — 3 implicit types with identical shape
Rectangle { property int padding: 10; property color accent: "blue" }
Rectangle { property int padding: 10; property color accent: "red" }
Rectangle { property int padding: 10; property color accent: "green" }

// GOOD — 1 explicit type, 3 instances
// AccentRect.qml
Rectangle { property int padding: 10; property color accent: "blue" }
```

### 4.5 Prefer QObject singletons over pragma library scripts
**Severity: MEDIUM**

`pragma library` scripts allocate on the JavaScript heap and create separate scope chains. QObject singletons consume less JS heap memory and are typed (enabling qmlcachegen optimization and QML Language Server support).

---

## 5. Rendering Performance

### 5.1 Clipping is NOT an optimization -- it increases cost
**Severity: CRITICAL**

`clip: true` creates a `QSGClipNode` that:
- Prevents the renderer from batching across the clip boundary
- Forces scissor or stencil operations
- Breaks batch roots, preventing geometry merging

Clipping in a delegate is especially destructive since every delegate instance becomes its own isolated batch.

Alternatives to clipping:
- Use `Image` with `QQuickImageProvider` for cropped images
- Use `Text.elide` instead of clipping text
- Use opaque `Rectangle` overlays to cover overflow
- Redesign layout to avoid overflow

### 5.2 layer.enabled is expensive -- use sparingly and temporarily
**Severity: HIGH**

`layer.enabled: true` forces the item subtree to render into an off-screen FBO (framebuffer object), then composites it as a texture. Costs:
- Extra render pass for the FBO
- Increased GPU memory for the texture
- The layered item CANNOT be batched with other items
- Invalidation causes full subtree re-render

Legitimate uses: opacity applied to a group, shader effects, caching a complex static subtree during animation. Disable the layer as soon as the effect is no longer needed.

### 5.3 Prefer `visible: false` over `opacity: 0`
**Severity: MEDIUM**

`visible: false` removes the item from the scene graph entirely (no rendering cost). `opacity: 0` still processes the item in the translucent pass. However, neither stops binding evaluation.

The one case where `opacity: 0` is better: when you need the item to retain its layout space and continue receiving key events.

### 5.4 Opaque content renders significantly faster than translucent
**Severity: HIGH**

The scene graph renderer has separate opaque (front-to-back, no blending) and translucent (back-to-front, with blending) passes. Opaque items:
- Can be freely reordered for optimal batching
- Use the depth buffer for early-z rejection
- Skip GL_BLEND entirely

A single translucent pixel in a texture causes the ENTIRE item to be treated as translucent. Use JPEG/BMP instead of PNG when transparency is not needed.

### 5.5 Avoid painting the same area multiple times
**Severity: MEDIUM**

Use `Item` (invisible) as a layout root instead of `Rectangle` (paints a filled rect). A colored Rectangle behind another opaque child causes overdraw.

### 5.6 Minimize ShaderEffect in delegates
**Severity: HIGH**

Each ShaderEffect breaks batching (unique material state). In a delegate, this means N separate draw calls for N visible delegates. Pre-render effects into image assets (e.g., BorderImage for shadows) whenever possible. The Spyro Soft case study showed replacing DropShadow with pre-rendered 9-slice images yielded 3x FPS improvement and 50% memory reduction.

### 5.7 Disable Image.smooth when unnecessary
**Severity: LOW**

`smooth: true` (default) enables bilinear filtering. At native resolution, it adds GPU cost with no visual benefit. Disable for pixel-art or when image size matches display size exactly.

### 5.8 Use anchors instead of binding-based positioning
**Severity: MEDIUM**

Anchor resolution is handled by the C++ layout system directly, bypassing the JavaScript binding evaluator. Binding-based positioning (`x: other.x + 10`) creates JavaScript bindings that evaluate through the QML engine.

```qml
// SLOWER
Rectangle { x: rect1.x; y: rect1.y + rect1.height; width: rect1.width - 20 }

// FASTER
Rectangle { anchors.left: rect1.left; anchors.top: rect1.bottom; anchors.rightMargin: 20 }
```

### 5.9 Target fewer than 10 batches, at least 3-4 opaque
**Severity: MEDIUM (diagnostic)**

Use `QSG_VISUALIZE=batches` and `QSG_RENDERER_DEBUG=render` to inspect batch counts. Many small unmerged batches indicate excessive material/state fragmentation.

### 5.10 Avoid antialiasing via `antialiasing: true` on performance-critical items
**Severity: LOW**

Vertex-based antialiasing adds extra vertices at edges and forces blending, preventing the item from being treated as opaque. If antialiasing is needed, prefer MSAA via `QSurfaceFormat` (global, enables early-z).

---

## 6. Signal / Slot Efficiency

### 6.1 Queued connections add copy + queue overhead
**Severity: MEDIUM**

Default QML signal connections are direct (synchronous). Queued connections (cross-thread) copy all arguments and queue them. Avoid exposing large value types (structs, vectors) in signals that may cross thread boundaries.

### 6.2 Multiple property changes trigger multiple binding evaluations
**Severity: HIGH**

If a C++ method emits `widthChanged()` then `heightChanged()`, any binding that depends on both will evaluate twice (once with new width + old height, once with new width + new height). Group related changes:
- Use a single "geometryChanged" signal in C++ where feasible
- Or defer signal emission until all properties are updated (manual `blockSignals` / batch approach)

### 6.3 Qt.callLater batches multiple calls to the same function
**Severity: MEDIUM**

`Qt.callLater(fn)` defers execution to the next event loop iteration. If called multiple times with the same function, it executes only once. Useful for coalescing updates:

```qml
function updateLayout() { /* expensive */ }
onWidthChanged: Qt.callLater(updateLayout)
onHeightChanged: Qt.callLater(updateLayout)  // only one call if both change in same frame
```

### 6.4 Use FrameAnimation (Qt 6.4+) instead of Timer for per-frame work
**Severity: MEDIUM**

`Timer { interval: 16 }` has an extra event loop roundtrip and does not sync with the rendering loop. `FrameAnimation` runs in sync with Qt Quick's animation framework, avoiding drift and extra overhead.

---

## 7. JavaScript in QML

### 7.1 Cache property lookups in local variables inside loops
**Severity: HIGH**

Each property access in JavaScript goes through the QML engine's object wrapper, resolving the property by name. In tight loops, this adds up:

```qml
// BAD — rect.color resolved 2000 times
for (var i = 0; i < 1000; ++i) {
    use(rect.color.r);
    use(rect.color.g);
}

// GOOD — resolved once
var c = rect.color;
for (var i = 0; i < 1000; ++i) {
    use(c.r);
    use(c.g);
}
```

### 7.2 Use temporary accumulators, not incremental property updates
**Severity: HIGH**

Updating a QML property inside a loop fires change signals on every iteration:

```qml
// BAD — N change signals, N binding re-evaluations
for (var i = 0; i < data.length; ++i)
    accumulatedValue += data[i];

// GOOD — 1 change signal
var temp = accumulatedValue;
for (var i = 0; i < data.length; ++i)
    temp += data[i];
accumulatedValue = temp;
```

### 7.3 Avoid running JavaScript during animations
**Severity: HIGH**

JavaScript executes on the main/GUI thread. Complex JS during an animation causes frame drops. Move computation to C++ `Q_INVOKABLE` methods or pre-compute before the animation starts.

### 7.4 Never use eval() in QML
**Severity: CRITICAL**

`eval()` prevents all compiler optimizations, creates new execution contexts, and forces the full JavaScript engine path for the enclosing scope.

### 7.5 Never delete object properties
**Severity: HIGH**

`delete obj.prop` de-optimizes the object's hidden class in V8/V4, falling back to dictionary mode for all subsequent property accesses on that object.

### 7.6 Avoid string-to-URL conversions
**Severity: MEDIUM**

Assigning a string to a `url`-typed property triggers `QUrl` construction, which is expensive. Declare properties with the correct type:

```qml
// BAD — runtime conversion on every assignment
property string avatar: ""  // used as Image.source

// GOOD — no conversion
property url avatar: ""
```

### 7.7 Modify copy sequences, not reference sequences
**Severity: HIGH**

A `Q_PROPERTY` list is a "reference sequence" -- each element write triggers a full read-modify-write cycle on the entire property. A local JS array is a "copy sequence" with direct access. Batch mutations on a copy, then assign back:

```qml
// BAD — each iteration: read full list, modify element, write full list
for (var j = 0; j < 100; ++j)
    qrealListProperty[j] = j;

// GOOD — modify local copy, single write-back
let data = [...qrealListProperty];
for (var j = 0; j < 100; ++j)
    data[j] = j;
qrealListProperty = data;
```

### 7.8 Type-annotate all function parameters and return types
**Severity: HIGH**

The QML compiler (qmlcachegen/qmlsc) cannot compile functions without type annotations. Untyped functions fall back to interpreted JavaScript:

```qml
// BAD — interpreted at runtime
function area(w, h) { return w * h; }

// GOOD — compiled to C++ by qmlcachegen
function area(w: double, h: double) : double { return w * h; }
```

---

## 8. Qt Quick Controls & Type System

### 8.1 Use concrete types, never `property var` unless truly variant
**Severity: HIGH**

`property var` prevents qmlcachegen from generating efficient C++ code for bindings. It also prevents QML Language Server diagnostics. Use the most specific type available:

```qml
// BAD
property var count: 0
property var name: ""
property var items

// GOOD
property int count: 0
property string name: ""
property list<Item> items
```

### 8.2 Use qualified property lookups (id-based, not parent-based)
**Severity: HIGH**

`parent.myProp` resolves against `Item`, which does not know about your custom properties. The compiler cannot generate typed access. Use the id:

```qml
Item {
    id: root
    property int size: 10
    Rectangle {
        width: root.size      // GOOD — compiler knows root's type
        // width: parent.size  // BAD — parent is typed as Item, no 'size' property
    }
}
```

### 8.3 Use `pragma ComponentBehavior: Bound`
**Severity: HIGH**

Without this pragma, delegates cannot safely reference IDs outside their component boundary, and the compiler cannot optimize those references. With it, delegates are bound to their defining context, enabling ID-based lookups and compilation:

```qml
pragma ComponentBehavior: Bound
```

Caveat: model data must be accessed via `required property`, not context variables.

### 8.4 Do not assign an `id` to custom style implementations of controls
**Severity: MEDIUM**

Qt Quick Controls uses an optimization that avoids creating both the default and custom background/contentItem. If you assign an `id` to the custom implementation, this optimization is disabled and both items are created:

```qml
Button {
    // BAD — disables the optimization, both default and custom background created
    background: Rectangle { id: bg; color: "red" }

    // GOOD — optimization active, only custom background created
    background: Rectangle { color: "red" }
}
```

### 8.5 Basic style is the fastest Qt Quick Controls style
**Severity: MEDIUM**

Material and Universal styles require more scene graph nodes and shader effects. For a desktop shell where you control the visual design entirely, either use Basic style or build directly on raw `Item` / `Rectangle` types to avoid Controls overhead.

### 8.6 Do not import QtQuick.Controls inside custom style files
**Severity: MEDIUM**

Importing `QtQuick.Controls` inside a style implementation file prevents the QML compiler from generating optimized code for that file.

### 8.7 Prefer compile-time style selection
**Severity: LOW**

Set `QT_QUICK_CONTROLS_STYLE` at compile time (via CMake) rather than runtime. This lets qmlcachegen know the exact style and generate optimized bindings. The QtQuick.Controls plugin is not loaded at all.

---

## 9. Images

### 9.1 Always set sourceSize to display dimensions
**Severity: HIGH**

Without `sourceSize`, the full-resolution image is kept in GPU memory. A 4000x3000 photo displayed at 400x300 wastes 10x the memory:

```qml
Image {
    source: "photo.jpg"
    sourceSize: Qt.size(width, height)  // decode at display size
}
```

Caveat: changing `sourceSize` triggers a full image reload.

### 9.2 Use asynchronous: true for local images
**Severity: MEDIUM**

Image decoding on the GUI thread blocks rendering. `asynchronous: true` decodes in a worker thread. Remote images are already async by default.

### 9.3 Disable cache for large one-off images
**Severity: MEDIUM**

`cache: false` prevents large wallpapers/photos from evicting small UI icons from the texture cache.

### 9.4 Pre-compose visual effects into image assets
**Severity: HIGH**

Shadows, glows, and decorations computed at runtime via ShaderEffect are expensive per frame. Pre-render them into PNG/9-slice images. This converts per-frame GPU cost into a one-time asset cost.

---

## 10. Text

### 10.1 Use Text.PlainText or Text.StyledText, never Text.RichText
**Severity: MEDIUM**

| Format | Cost | Use when |
|--------|------|----------|
| `PlainText` | Lowest | No formatting needed |
| `StyledText` | Moderate | Bold, italic, color, inline images |
| `AutoText` | Moderate + parse cost | Unknown format (avoid) |
| `RichText` | High (full HTML parser) | Almost never needed |

### 10.2 Use Text.elide instead of clipping for overflow
**Severity: MEDIUM**

`Text { elide: Text.ElideRight }` is far cheaper than `Text { clip: true }` because it avoids the clip node overhead and keeps the text in its parent's batch.

---

## 11. Startup Optimization Summary

| Priority | Technique |
|----------|-----------|
| Critical | Profile first (QML Profiler, `QSG_RENDERER_DEBUG=render`) |
| Critical | Lazy-load non-initial-screen content with `Loader { active: false }` |
| High | Use `asynchronous: true` on non-first-screen Loaders |
| High | Pre-compile QML (qmlcachegen / Qt Quick Compiler) |
| High | Batch model population (see rule 1.1) |
| Medium | Chain N async Loaders matching CPU core count |
| Medium | Optimize image sizes with optipng, set sourceSize |
| Medium | Minimize initial delegate complexity |
| Low | Prefer declarative bindings over imperative onCompleted handlers |

---

## 12. Diagnostic Environment Variables

| Variable | Purpose |
|----------|---------|
| `QSG_VISUALIZE=batches` | Color-code batches to see merging |
| `QSG_VISUALIZE=clip` | Highlight clipped regions in red |
| `QSG_VISUALIZE=overdraw` | 3D view showing overdraw depth |
| `QSG_VISUALIZE=changes` | Flash items that cause scene graph changes |
| `QSG_RENDERER_DEBUG=render` | Print batch counts, opaque/translucent stats |
| `QSG_INFO=1` | Print scene graph backend info |
| `qt.qml.gc.statistics` | GC statistics (reserved space, timing) |
| `qt.qml.gc.allocatorStats` | Detailed allocation statistics |
| `qt.qml.binding.removal` | Log when bindings are broken by imperative assignment |

---

## Sources

- [Qt 6.11 Performance Considerations and Suggestions](https://doc.qt.io/qt-6/qtquick-performance.html)
- [Qt 6.11 Scene Graph Default Renderer](https://doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph-renderer.html)
- [Qt 6.11 JavaScript Memory Management](https://doc.qt.io/qt-6/qtqml-javascript-memory.html)
- [Qt 6.11 QML Script Compiler](https://doc.qt.io/qt-6/qtqml-qml-script-compiler.html)
- [Qt Blog: Optimizing QML for Compilation to C++](https://www.qt.io/blog/optimizing-your-qml-application-for-compilation-to-c)
- [Qt Blog: Performance Benefits of the New Qt Quick Compiler](https://www.qt.io/blog/the-numbers-performance-benefits-of-the-new-qt-quick-compiler)
- [KDAB: 10 Tips for Faster QML](https://www.kdab.com/10-tips-to-make-your-qml-code-faster-and-more-maintainable/)
- [KDAB: QML Engine Internals Part 2 - Bindings](https://www.kdab.com/qml-engine-internals-part-2-bindings/)
- [KDAB: QML Engine Internals Part 3 - Binding Types](https://www.kdab.com/qml-engine-internals-part-3-binding-types/)
- [KDAB: QML Component Design - Two-Way Binding Problem](https://www.kdab.com/qml-component-design/)
- [KDAB: Analyzing Performance of QtQuick Applications](https://www.kdab.com/analyzing-performance-qtquick-applications/)
- [basysKom: Speedup QML List Scrolling](https://www.basyskom.de/en/speedup-your-qt-qml-list-scrolling-on-lowend-devices/)
- [Spyro Soft: Qt Quick QML Performance Optimization](https://spyro-soft.com/expert-hub/qt-quick-qml-performance-optimisation)
- [Qt Wiki: Performance Tips](https://wiki.qt.io/Performance_tip_QML_other)
- [Qt 6.11 ListView](https://doc.qt.io/qt-6/qml-qtquick-listview.html)
- [Qt 6.11 Customizing Qt Quick Controls](https://doc.qt.io/qt-6/qtquickcontrols-customize.html)
