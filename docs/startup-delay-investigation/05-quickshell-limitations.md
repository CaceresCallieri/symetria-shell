# Quickshell/Qt Framework Limitations

## Limitation 1: `qs.modules.*` Paths Don't Resolve in URL-Loaded Files

**Description:** When a QML file is loaded via `Loader.setSource(url, props)`, `Loader.source = url`, or `LazyLoader { source: url }`, the loaded file CANNOT use `qs.modules.*` import paths. These paths are Quickshell-specific and only available in files loaded through the normal directory-import chain.

**Error message:** `module "qs.modules.bar" is not installed`

**Workaround:** Use relative path imports: `import "../../bar"` instead of `import qs.modules.bar`. This resolves correctly relative to the loaded file's location.

**What DOES resolve in URL-loaded files:**
- `qs.services` ✓
- `qs.config` ✓
- `qs.components` ✓ (and submodules like `qs.components.containers`)
- `qs.utils` ✓
- `Quickshell` ✓
- `Quickshell.Wayland` ✓
- `Quickshell.Hyprland` ✓
- `QtQuick` ✓
- Relative directory imports (`import ".."`, `import "../../bar"`) ✓

**What does NOT resolve:**
- `qs.modules.*` paths ✗

**Impact:** Cannot use `Loader.setSource()` to defer compilation of files that import `qs.modules.*`. Must either use relative imports or keep files in eagerly-scanned directories.

---

## Limitation 2: Sibling Types Don't Resolve in URL-Loaded Files

**Description:** When a file is loaded via URL, it does NOT have implicit access to sibling QML files in the same directory. In normally-imported files, all QML siblings are automatically available as types.

**Example:** `NotificationsOverlay.qml` references `Content {}` (a sibling file). When loaded via URL Loader, error: `Content is not a type`.

**Workaround:** The loaded file can `import "."` to explicitly import its own directory, making siblings available. Alternatively, restructure to avoid sibling type references.

---

## Limitation 3: Variants Forces Synchronous Compilation

**Description:** Quickshell's `Variants` component creates one instance per model item (e.g., per screen). When a `Loader { asynchronous: true }` or `LazyLoader { loading: true }` is placed inside a Variants instance, the async loading is forced to complete synchronously.

**Source:** Quickshell documentation: "Variants does not support async loading inside LazyLoader."

**Impact:** Cannot use Variants + async Loader to defer heavy module compilation. The entire import chain compiles synchronously when the Variants instance is created.

**Tested approaches that failed:**
- `Loader { asynchronous: true }` inside Variants → blocks synchronously
- `LazyLoader { loading: true; source: url }` inside Variants → blocks synchronously
- `Timer { interval: 0 }` + `setSource()` inside Variants → Timer fires after component creation, but setSource still blocks

---

## Limitation 4: Quickshell.Services.Notifications Blocks Atomically

**Description:** The `Quickshell.Services.Notifications` C++ module performs blocking D-Bus notification daemon registration during initialization. This blocks the QML main thread for ~19 seconds. The blocking is atomic — it cannot be broken into incremental chunks by any QML-level mechanism.

**Proof:** Adding just `import Quickshell.Services.Notifications` to a bare window file (zero component creation) causes the full 19-second freeze.

**Related:** `import Quickshell.Widgets` also triggers a ~19-second freeze — likely a dependency on the same D-Bus registration or icon theme scanning.

**Impact:** Cannot defer notification system initialization. The freeze happens whenever any QML file that imports these modules is compiled, regardless of async Loader settings.

---

## Limitation 5: `sourceComponent` Compiles Eagerly

**Description:** `Loader { sourceComponent: FooType {} }` compiles the `FooType` QML when the **parent file** is compiled, not when the Loader activates. Only instantiation is deferred.

**Contrast:** `Loader { source: "Foo.qml" }` defers BOTH compilation and instantiation until the Loader activates (or source is set).

**Impact:** Using `sourceComponent` for heavy types provides no startup benefit. Must use `source` (URL string) or `setSource()` for true deferred compilation.

---

## Limitation 6: LazyLoader Cannot Pass Initial Properties with `source`

**Description:** Quickshell's `LazyLoader { source: url; loading: true }` doesn't support passing initial property values to the loaded component (unlike `Loader.setSource(url, {props})`).

**Impact:** Required properties on the loaded component cannot be set. Must use workarounds like global state or singleton services.

---

## Recommendations for Quickshell Upstream

1. **Make `qs.modules.*` paths available in URL-loaded files** — This would enable true deferred loading of heavy modules via `Loader.setSource()`.

2. **Support async loading inside Variants** — Allow `LazyLoader { loading: true }` to work incrementally even within Variants instances.

3. **Make `Quickshell.Services.Notifications` non-blocking** — Move D-Bus registration to a background thread or make it lazy (initialize on first notification access).

4. **Add `LazyLoader.setSource(url, props)`** — Combine LazyLoader's incubation controller with Loader's property-passing API.
