# Project Standards — Symmetria Shell

> QML 6 / JavaScript / QuickShell desktop shell for Hyprland (Wayland).
> These standards are consumed by `/tech-debt` and `/code-review` skills.
> For full QML performance reference, see `docs/qml-performance-guidelines.md`.

## Stack

QML 6.11+, JavaScript (QuickShell runtime), C++ plugins (Qt 6), Python helper scripts, Shell scripts (zsh/bash)

## Critical Paths

These directories have the highest impact — prioritize findings here:

- `services/` — Singleton services that load/persist state (Notifs, Clipboard, Audio, Network, Colours)
- `modules/drawers/` — Drawer system managing visibility, input regions, focus grabs
- `modules/bar/` — Always-visible bar with popouts — performance-critical (renders every frame)
- `shell.qml` — Entry point, Variants per-screen, startup sequence
- `plugin/src/` — C++ native plugins (must rebuild on Qt upgrades)
- `config/` — Configuration system bridging JSON ↔ QML properties

---

## Code Patterns

### Enforce

#### P0 — Critical (bugs, freezes, data loss)

- **Batch list property mutations** — NEVER `push()`, `splice()`, or `unshift()` on a QML list property inside a loop. Build a local JS array, assign once. Each mutation triggers ALL downstream bindings, creating O(n²) cost. This caused a 23-second startup freeze with 6,890 notifications. See `docs/startup-delay-investigation/11-postmortem-and-learnings.md`.
  ```qml
  // FORBIDDEN
  for (const item of data)
      root.list.push(createItem(item));

  // REQUIRED
  const temp = [];
  for (const item of data)
      temp.push(createItem(item));
  root.list = temp;
  ```

- **Set model item state BEFORE array assignment** — Repeater/ListView creates delegates synchronously on model change. Properties set after assignment are too late.
  ```qml
  // FORBIDDEN
  root.list = [newItem, ...root.list];
  newItem.status = "active";  // delegate already created with stale state

  // REQUIRED
  newItem.status = "active";
  root.list = [newItem, ...root.list];
  ```

- **Use `required foo` not `required property type foo` in delegates** — The latter creates a shadow property that silently breaks delegate bindings from the model. The former uses the existing inherited property.

- **Never call `gc()` during interactive use** — Blocks the GUI thread for hundreds of milliseconds. Qt 6.8+ runs GC incrementally.

- **Never use `eval()` in QML JavaScript** — Prevents all compiler optimizations. (Note: `Qalculator.eval()` is a C++ plugin method, not JS eval — that's fine.)

- **Destroy dynamic objects explicitly** — `Component.createObject()` objects with `JavaScriptOwnership` depend on GC timing. Call `.destroy()` explicitly when done. Always pass a parent to `createObject()`.

#### P1 — High (performance, correctness)

- **Type all function parameters and return types** — Untyped functions fall back to interpreted JavaScript. The QML compiler (qmlcachegen) can only compile typed functions to C++.
  ```qml
  // BAD — interpreted at runtime
  function process(items, count) { return items.slice(0, count); }

  // GOOD — compiled to C++
  function process(items: list<Item>, count: int): list<Item> { return items.slice(0, count); }
  ```

- **Use concrete types, not `property var`** — `property var` prevents qmlcachegen optimization and QML Language Server diagnostics. Use the most specific type: `int`, `string`, `real`, `color`, `list<Type>`, `url`, etc. Reserve `var` only for truly variant data (JS objects with dynamic shape, Map, Set).

- **Use id-based property lookups** — `parent.myProp` resolves against `Item` which doesn't know custom properties. `root.myProp` (id-based) enables typed access and compilation.
  ```qml
  Item {
      id: root
      property int size: 10
      Rectangle {
          width: root.size      // GOOD — compiler knows root's type
          // width: parent.size  // BAD — parent typed as Item, no 'size'
      }
  }
  ```

- **Use `property url` for image/file paths** — `property string` triggers `QUrl` construction on every assignment to `Image.source`. Declare as `url` to avoid runtime conversion.

- **Cache property lookups in loops** — Each QML property access goes through the engine's object wrapper. Cache in a local variable for tight loops.

- **Use temporary accumulators** — Never update a QML property inside a loop. Each update fires change signals. Accumulate in a local variable, assign once at the end.

- **Type-annotate IPC handler functions** — QuickShell IpcHandler functions support max 10 args, types must be explicit: `string`, `int`, `bool`, `real`, `color`. Untyped IPC functions silently fail.

- **Clear QML cache after every QML/SVG/asset change** — `rm -rf ~/.cache/quickshell/qmlcache`. Stale cache causes phantom bugs that waste investigation time.

#### P2 — Medium (maintainability, minor performance)

- **All QML root elements should have an `id`** — Enables debugging, profiling, and id-based lookups from children.

- **Use anchors over binding-based positioning** — Anchors are resolved by the C++ layout system directly, bypassing the JS binding evaluator.

- **Use `Text.PlainText` or `Text.StyledText`** — Never `Text.RichText` (full HTML parser). Never `Text.AutoText` (parse cost to auto-detect).

- **Use `Text.elide` instead of `clip: true` for text overflow** — Elide avoids clip node overhead and keeps text in the parent's batch.

- **Prefer `visible: false` over `opacity: 0`** — `visible: false` removes from scene graph entirely. `opacity: 0` still processes in the translucent pass.

- **Set `sourceSize` on non-icon Image elements** — Without it, full-resolution images stay in GPU memory. A 4000×3000 photo at 400×300 wastes 10× memory.

- **Use `asynchronous: true` on Image for large files** — Image decoding on the GUI thread blocks rendering. Remote images are already async.

- **Shell scripts must pass `shellcheck`** — All scripts in `scripts/`, `utils/`, and dotfiles helper scripts.

### Avoid

#### P0 — Forbidden

- **`root.list.push()` inside any loop** — See batch mutation rule above. This is the single most dangerous pattern in this codebase. Severity: caused 23s freeze, 47.5M wasted filter iterations.

- **`required property type name` in delegates** — Creates shadow property. Use `required name` to bind the existing one.

- **`eval()` in QML JavaScript** — Security and performance hazard. (C++ plugin `.eval()` methods are fine.)

- **`delete obj.prop`** — De-optimizes the object's hidden class, forcing dictionary mode for all subsequent accesses.

#### P1 — Strongly Discouraged

- **`clip: true` in delegates** — Each clip creates a `QSGClipNode` that breaks batch merging. In a Repeater/ListView delegate, this means N separate batches for N items. Use `Text.elide`, opaque overlays, or layout redesign instead.

- **`clip: true` anywhere without justification** — Clipping is NOT an optimization. It increases rendering cost. Acceptable only when content genuinely overflows and no alternative exists (e.g., rounded corners on images via `ClippingRectangle`).

- **Permanent `layer.enabled: true`** — Forces off-screen FBO rendering. Legitimate for temporary animation effects (opacity groups, shader effects). Must be disabled when the effect ends. Never leave permanently enabled on static content.

- **`ShaderEffect` in delegates** — Each instance breaks batching (unique material state). Pre-render effects into image assets (9-slice PNG for shadows). Spyro Soft case study: 3× FPS improvement and 50% memory reduction from this change alone.

- **`property var` for known types** — Use `int`, `string`, `real`, `bool`, `color`, `url`, `list<Type>`, or specific QML types.

- **`parent.customProperty`** — Untyped access. Use id-based references instead.

- **`ListModel.dynamicRoles: true`** — Disables internal type optimizations. Qt docs: "much worse performance."

- **String concatenation for URLs** — Use template literals or `Qt.resolvedUrl()` instead of `"file://" + path`.

#### P2 — Discouraged

- **`Repeater` for scrollable content over ~30 items** — Use `ListView` with `reuseItems: true` for large/dynamic lists.

- **Intermediate binding properties with single consumers** — Cascading chains (A → B → C) where B has one reader add evaluation passes. Flatten to a single binding unless B is reused.

- **`Timer { interval: 0 }` for post-layout work** — Fires BEFORE ColumnLayout computes `implicitHeight` (polish phase). Use `onImplicitHeightChanged` for reliable post-polish values.

- **`antialiasing: true` on performance-critical items** — Adds extra vertices at edges and forces blending. Use MSAA via `QSurfaceFormat` for global AA.

---

## Performance

### Thresholds

| Metric | Acceptable | Warning | Critical |
|--------|-----------|---------|----------|
| Shell startup to interactive | < 1.5s | 1.5–3s | > 5s |
| Notification count (persisted) | < 1,000 | 1,000–5,000 | > 5,000 |
| State directory total size | < 500KB | 500KB–2MB | > 2MB |
| Scene graph batches (per window) | < 10 | 10–20 | > 30 |
| Function body length (QML JS) | < 50 lines | 50–80 | > 100 |
| QML file length | < 300 lines | 300–500 | > 600 |

### Data-Dependent Performance

This project has data-dependent bugs that only manifest at scale. Services that persist state (notifications, clipboard, calculator history) MUST be tested with realistic data volumes, not just fresh-install state.

**The 30-second diagnostic:**
```bash
# Check notification count
python3 -c "import json; d=json.load(open('$HOME/.local/state/symmetria/notifs.json')); print(f'Notifications: {len(d)}')" 2>/dev/null || echo "Notifications: 0"

# Check state directory size
du -sh ~/.local/state/symmetria/ 2>/dev/null
```

### Binding Cascade Awareness

QML uses push-based dependency tracking with NO batching. When a captured property changes, its NOTIFY signal immediately triggers re-evaluation of every binding that references it. Three property changes in the same method = three separate binding evaluation passes.

**Audit checklist for new list-loading code:**
1. Is the list property mutated in a loop? → Batch it
2. How many computed properties bind to this list? → Each is a multiplier
3. What's the maximum realistic data size? → Test at 2× that size
4. Are there cascading bindings (A → B → C)? → Flatten if B has one reader

### QuickShell-Specific Performance

- **Variants forces synchronous creation** — `Loader { asynchronous: true }` inside Variants is forced synchronous. Keep Variants delegates lightweight; defer heavy content to singletons or LazyLoader outside Variants.
- **LazyLoader deadlock** — All windows in LazyLoaders = nothing loads. Always have at least one eagerly-loaded window.
- **`sourceComponent` compiles eagerly** — Only instantiation is deferred. Use `source` (URL string) for true deferred compilation + instantiation.
- **URL-loaded files can't resolve `qs.modules.*`** — Files loaded via `Loader.source` or `LazyLoader { source: url }` cannot import sibling module types. Use relative imports or restructure.

---

## Architecture

### Service Singleton Rules

- Services load state via `FileView` + `JsonAdapter` or manual JSON parsing in `onLoaded`
- **State loading MUST use batch assignment** — Any `onLoaded` handler that populates a list property must build locally and assign once
- Heavy singletons block the main thread during initialization — order matters in `shell.qml` imports
- Use `PersistentProperties` with `reloadableId` for hot-reload state survival
- IPC handlers: max 10 args, all explicitly typed, return types explicit

### Drawer System Rules

- Input regions use XOR mask — expanding `mainRect` SHRINKS clickable area (counterintuitive)
- Bar must stay OUTSIDE `mainRect` to receive input
- Panel `Intersection.Subtract` regions RESTORE those areas to the input region
- Overlay MouseAreas need both `enabled` AND `visible` guards — `visible: true` + `enabled: false` still shadows `cursorShape`

### Configuration Hierarchy

```
~/.config/symmetria/shell.json  (JSON overrides — ALWAYS WIN)
    ↓ overrides
config/*.qml                     (QML defaults — version controlled)
```

**JSON overrides always win.** If you edit a QML default but the value exists in `shell.json`, your change has no effect. Always check `shell.json` first when debugging config issues.

### Process Management

- Binary name is `qs`, NOT `quickshell` — `pkill quickshell` does NOTHING
- Kill: `pkill -x qs` (be careful — kills ALL QuickShell instances)
- Check: `pgrep -fa qs | grep -v grep | grep -v zsh | grep -v python | grep -v claude`
- NEVER launch the shell from automated scripts — the user runs it as their active desktop

---

## Testing

- **Multiple measurements required** — Never use single measurements for benchmarks. Run 3+ times, report min/median/max.
- **Kill all instances before benchmarks** — Multiple `qs` instances cause 2–3× measurement contamination. Always `pkill -x qs` and verify with `pgrep` before timing.
- **Test with realistic data** — Fresh install (0 notifications) ≠ production (thousands). Services must be tested at scale.
- **Clear QML cache between runs** — `rm -rf ~/.cache/quickshell/qmlcache` for clean measurements.

---

## Security

- **Never commit API keys or tokens** — STT keys, weather API keys, etc. go in `~/.secrets/env` (mode 600, directory mode 700)
- **Askpass dialog** — Handles `sudo -A` via IPC to running shell. Never log or persist passwords.
- **Shell scripts** — Check `command -v` before using external tools. Use `set -euo pipefail` (bash) or `setopt ERR_EXIT PIPE_FAIL` (zsh).

---

## Documentation

- `CLAUDE.md` — Agent-facing project context (architecture, commands, pitfalls)
- `docs/qml-pitfalls.md` — Consolidated QML gotchas with code examples
- `docs/qml-performance-guidelines.md` — Full 59-rule performance reference with severity ratings
- `docs/startup-delay-investigation/` — Complete investigation timeline and postmortem
- `docs/drawer-extension-guide.md` — How to add new drawer panels
- `*.investigation.md` files — Debug session logs for past issues

---

## Known Anti-Pattern Hotspots (from audit)

These are known instances of discouraged patterns in the current codebase. When working near these files, consider fixing them:

| Pattern | Count | Highest-Risk Files |
|---------|-------|--------------------|
| List mutation in loops | 6 | `services/Calculator.qml:150`, `modules/bar/popouts/TrayMenu.qml:104` |
| `clip: true` | ~50 | Spread across buttons, dialogs, popouts, bar components |
| `layer.enabled` (permanent) | ~32 | Mostly with OpacityMask, Colouriser, MultiEffect |
| `property var` (should be typed) | ~328 | Widespread — prioritize services/ and modules/drawers/ |
| Untyped function params | ~4 | `services/VPN.qml:38`, `services/Notifs.qml:316` |

---

## Qt / QuickShell Version Notes

- **Qt HTTP/2 bug** — `QNetworkAccessManager` enables HTTP/2 by default. Some servers (e.g., `ipinfo.io`) cause silent protocol errors. Disable per-request: `Http2AllowedAttribute = false`.
- **Qt 6.11.0** — Current version. Rebuilding QuickShell and all C++ plugins required after Qt upgrades.
- **QuickShell pragmas** — Must appear before any `import` in `shell.qml`. Currently using `QT_QPA_PLATFORM=wayland`.
