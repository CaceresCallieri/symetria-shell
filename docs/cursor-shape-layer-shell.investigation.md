# Investigation: cursor-shape-layer-shell

**Started**: 2026-03-07
**Status**: Finalized

---

## Pass 1

**Timestamp**: 2026-03-07
**Status**: narrowing

### Findings
- Regular Qt QML windows (xdg-shell) **do** show cursor changes — confirmed by user running `qml6 /tmp/test_cursor.qml`
- **No** Quickshell layer-shell surface shows any cursor change: no hand cursor on buttons, no I-beam on text inputs, no cursor changes anywhere
- Hyprland advertises `wp_cursor_shape_manager_v1` v2 (confirmed via `wayland-info`)
- `libQt6WaylandClient.so` (Qt 6.10.2) has full `cursor-shape-v1` support compiled in — `QWaylandCursorShape` class wraps `wp_cursor_shape_device_v1`
- Quickshell (v0.2.1, git `1e4d804e`) has **zero** cursor handling code — no `setCursor`, no `changeCursor` overrides. Relies entirely on Qt defaults
- Quickshell's `LayerShellIntegration` inherits `QWaylandShellIntegrationTemplate` + `zwlr_layer_shell_v1`. Its `LayerSurface` inherits `QWaylandShellSurface` — no cursor method overrides
- `StateLayer.qml` (`components/StateLayer.qml`) correctly sets `cursorShape: Qt.PointingHandCursor` and `hoverEnabled: true` — hover effects (ripple, background change) DO work, confirming mouse events are delivered
- The drawers window (`Drawers.qml:195`) has `Interactions` — a full-window `CustomMouseArea` with `hoverEnabled: true`. The bar and all panels are **children** of this MouseArea

### Qt Cursor Flow (from source analysis of qtbase v6.10.2)
1. QML item cursor change → `QWaylandCursor::changeCursor(QCursor*, QWindow*)` (`src/plugins/platforms/wayland/qwaylandcursor.cpp:313`)
2. Stores cursor via `waylandWindow->setStoredCursor()` (line 327)
3. **Critical check** (line 332): `device->pointer()->focusWindow() == waylandWindow` — only sets cursor if pointer focus matches
4. Calls `device->setCursor()` → `mPointer->updateCursor()` (`qwaylandinputdevice.cpp:207`)
5. `updateCursor()` checks `mEnterSerial == 0` (line 209), gets shape from `seat()->mCursor.shape` (line 212)
6. If cursor-shape-v1 available (`mCursor.shape` exists, line 233): sends `set_shape(mEnterSerial, shape)` (line 237)
7. Otherwise falls back to wl_cursor theme rendering

### Code Paths
| File | Lines | Role |
|------|-------|------|
| `qtbase/src/plugins/platforms/wayland/qwaylandcursor.cpp` | 313-337 | `changeCursor()` — entry point, checks focusWindow match |
| `qtbase/src/plugins/platforms/wayland/qwaylandinputdevice.cpp` | 207-282 | `Pointer::updateCursor()` — sends protocol request |
| `qtbase/src/plugins/platforms/wayland/qwaylandinputdevice.cpp` | 660-698 | `pointer_enter()` — sets mFocus, mEnterSerial, calls updateCursor |
| `qtbase/src/plugins/platforms/wayland/qwaylandinputdevice.cpp` | 134-135 | Pointer constructor — creates QWaylandCursorShape if manager available |
| `qtbase/src/plugins/platforms/wayland/qwaylandwindow.cpp` | 1567-1595 | `restoreMouseCursor()` / `applyCursor()` — called on enter/leave |
| `qtbase/src/plugins/platforms/wayland/qwaylandwindow.cpp` | 388-393 | `fromWlSurface()` — maps wl_surface → QWaylandWindow |
| `quickshell/src/wayland/wlr_layershell/shell_integration.cpp` | - | Shell integration — no cursor overrides |
| `quickshell/src/wayland/wlr_layershell/surface.cpp` | - | LayerSurface — no cursor overrides |
| `components/StateLayer.qml` | 20-21 | Sets `cursorShape: Qt.PointingHandCursor`, `hoverEnabled: true` |
| `modules/drawers/Interactions.qml` | 69-70 | Full-window MouseArea, `hoverEnabled: true` |
| `modules/drawers/Drawers.qml` | 195-234 | Interactions wraps Panels + BarWrapper + AgentBar as children |

### Hypotheses
| # | Hypothesis | Confidence | Evidence |
|---|-----------|------------|----------|
| 1 | `QWaylandWindow::fromWlSurface()` returns nullptr for Quickshell's layer-shell surfaces, causing `pointer_enter()` to bail at line 668 ("Ignore foreign surfaces") → mFocus never set → focusWindow check in changeCursor always fails | HIGH | This single failure would explain ALL symptoms: no cursor changes on any surface, but events still work (events go through a different path). Layer-shell uses custom wl_surface creation that may not register in Qt's surface map |
| 2 | Quickshell creates QQuickWindow via `createQQuickWindow()` but the resulting window's QPlatformWindow handle doesn't match what focusWindow returns — identity mismatch in changeCursor's comparison | MED | Quickshell wraps windows with ProxiedWindow; if handle() returns a different object than what pointer_enter stored, the == check fails |
| 3 | The mEnterSerial stored in pointer_enter is stale/wrong for layer-shell surfaces, causing the compositor to reject set_shape requests | LOW | Would need WAYLAND_DEBUG to confirm; less likely since the serial mechanism is surface-agnostic |
| 4 | Quickshell's window recreation (reset/reinit) invalidates the stored focusWindow reference, causing the == check to fail intermittently → effectively always fails | LOW | Would only affect windows that get recreated, but ALL surfaces are affected |

### Eliminated
- **GTK cursor-shape-v1 incompatibility**: Not relevant — this is a Qt application, not GTK. The Hyprland discussion #5248 about GTK apps not supporting cursor-shape-v1 doesn't apply
- **Missing cursor-shape-v1 protocol support**: Eliminated — both Hyprland (compositor) and libQt6WaylandClient.so (client) have full support compiled in
- **Quickshell cursor override/suppression**: Eliminated — searched entire Quickshell codebase for "setCursor", "changeCursor", "cursor" in window code — zero results. No override exists
- **QML-level cursor shadowing by Interactions MouseArea**: Eliminated — QML cursor determination traverses children first (top-most item wins). Bar buttons are children of Interactions, so their cursor should take priority. Also, even text inputs (I-beam cursor) don't work, which have nothing to do with Interactions
- **Hyprland hardware cursor regression (#6065)**: Eliminated — that bug was about xcursor theme sticking, not about cursor-shape-v1 protocol. Also, regular Qt windows DO work
- **Missing hoverEnabled on specific MouseAreas**: Eliminated as root cause — even StateLayer.qml which has `hoverEnabled: true` and correctly sets `cursorShape` shows no cursor change. The issue is systemic, not per-component

### Errors & Symptoms
```
Symptom: Mouse cursor stays as default arrow on ALL Quickshell surfaces
- No hand cursor on buttons (StateLayer has cursorShape: Qt.PointingHandCursor)
- No I-beam cursor on text inputs (launcher search, askpass dialog)
- Hover effects DO work (ripple, background color changes)
- Click events DO work
- Regular Qt QML windows (xdg-shell) show correct cursors
```
Reproduction: Hover over any clickable element or text input in the Symmetria shell

### Next Steps
- [ ] **WAYLAND_DEBUG trace**: Start Quickshell with `WAYLAND_DEBUG=1` and grep for `cursor_shape|set_cursor|pointer_enter|pointer_leave` to see if cursor protocol requests are sent at all. This will definitively confirm/deny hypothesis #1
- [ ] **Check fromWlSurface mapping**: Search Quickshell source for how wl_surface is created for layer-shell windows — specifically whether `QWaylandSurface` is properly initialized so that `fromWlSurface()` can find it. Key file: `quickshell/src/wayland/wlr_layershell/surface.cpp` constructor
- [ ] **Test with a minimal Quickshell PanelWindow**: Create a standalone Quickshell config (different `-c` name) with just a PanelWindow containing a MouseArea with cursorShape — isolates whether ALL layer-shell surfaces are affected or just the drawers window
- [ ] **File upstream bug**: If WAYLAND_DEBUG confirms no cursor requests are sent, file a bug on git.outfoxxed.me/quickshell/quickshell with the trace and analysis

### Open Questions
- Does `QWaylandWindow::fromWlSurface()` work for Quickshell's layer-shell surfaces? The function uses `QWaylandSurface::fromWlSurface()` which relies on wl_surface proxy user_data. If Quickshell's surface creation bypasses Qt's surface management, this mapping breaks
- Does Quickshell use `QQuickRenderControl` or off-screen rendering that might create a different window/surface hierarchy than expected? (Search showed no QQuickRenderControl usage, but `createQQuickWindow()` needs investigation)
- Is this a known Quickshell issue? Forgejo search returned no results, but the search interface was unreliable

---

## Pass 2

**Timestamp**: 2026-03-07
**Status**: root-cause-identified

### Findings

**WAYLAND_DEBUG trace** (definitive):
- `wp_cursor_shape_device_v1#30` IS created on startup → cursor-shape-v1 protocol is bound ✓
- `wl_pointer#29.enter` events DO fire for Quickshell's `wl_surface#78` → `fromWlSurface()` works ✓ (eliminates hypothesis #1)
- `set_shape` IS called — but **only on pointer_enter**, and **always with shape=1 (default)**
- **Every** `set_shape` serial matches a `pointer_enter` serial exactly — confirmed via comm analysis
- **Zero** `set_shape` calls occur between enter/leave pairs (i.e., when hovering over buttons)
- 10 enter events, 11 set_shape calls (first enter triggers 2 set_shape calls)
- No other cursor shapes ever appear (no shape=28/pointer, no shape=38/text)

**Quickshell source analysis** (ProxiedWindow architecture):
- `ProxiedWindow` is a thin QQuickWindow subclass — does NOT override `handle()` or QPlatformWindow
- `window->create()` in `LayerSurfaceBridge::init()` creates the QPlatformWindow normally
- `dynamic_cast<QWaylandWindow*>(window->handle())` succeeds — the platform window IS a QWaylandWindow
- The wl_surface comes from `waylandWindow->waylandSurface()->object()` — standard Qt creation path
- No QQuickRenderControl usage — ProxiedWindow IS the QQuickWindow that renders the scene

**What this means:**
- `pointer_enter()` → `restoreMouseCursor()` → `updateCursor()` → `set_shape(serial, 1)` works
- `changeCursor()` → `setCursor()` → `updateCursor()` → `set_shape(serial, N)` does NOT happen
- Either `changeCursor()` is never called by Qt Quick's cursor propagation for Quickshell windows, OR the `focusWindow == waylandWindow` check fails, OR `setCursor`'s redundancy check short-circuits because cursor is already ArrowCursor

**Double set_shape on first enter:**
The first enter (serial 256937) produces TWO `set_shape(256937, 1)` calls. The first is from `pointer_enter → updateCursor()`. The second is likely from Qt Quick's `QQuickWindowPrivate::updateCursor()` triggering `changeCursor()` in response to the enter event — confirming the focusWindow check CAN pass. But both shapes are 1 (default), suggesting Qt Quick resolves the cursor as ArrowCursor even when the pointer enters over an area where items have non-default cursors.

### Updated Hypotheses
| # | Hypothesis | Confidence | Evidence |
|---|-----------|------------|----------|
| 5 | Qt Quick's internal cursor propagation (`QQuickDeliveryAgentPrivate::updateCursor()`) never resolves non-default cursors for Quickshell's ProxiedWindow. The QML `cursorShape` property IS set, but Qt Quick's hover/cursor delivery doesn't propagate cursor changes to the platform, possibly because the QQuickWindow's cursor handling is bypassed or broken when used as a layer-shell surface | HIGH | All set_shape calls use shape=1 (default). The double set_shape on first enter suggests changeCursor IS called (focusWindow check passes), but the cursor being set is always ArrowCursor. This points to Qt Quick's cursor resolution being broken, not the Wayland cursor pipeline |
| 6 | Quickshell's event delivery bypasses Qt Quick's normal input handling, preventing `QQuickDeliveryAgent` from tracking hover state and cursor changes. Events may be injected directly into items rather than going through QQuickWindow's event dispatch | MED | Quickshell has custom event handling; if mouse events bypass QQuickWindow::event(), the cursor delivery agent never updates |
| 2 | Window identity mismatch in changeCursor's comparison | LOW (downgraded) | ProxiedWindow doesn't override handle(). The double set_shape on first enter suggests the check DOES pass. Less likely than hypothesis #5 |

### Eliminated
- **Hypothesis #1 (fromWlSurface returns nullptr)**: ELIMINATED — WAYLAND_DEBUG shows `wl_pointer.enter` fires with valid surface, and `set_shape` is called (which requires successful fromWlSurface → mFocus → updateCursor chain)
- **Hypothesis #3 (stale mEnterSerial)**: ELIMINATED — set_shape IS sent successfully on enter. The serial mechanism works. The issue is that set_shape is never sent BETWEEN enter/leave events
- **Not a known Quickshell issue**: Searched GitHub mirror (quickshell-mirror/quickshell) — no issues about cursor shape. Issue #530 is about cursor crashes on display switching, unrelated

### Code Paths (updated)
| File | Lines | Role |
|------|-------|------|
| `qwaylandinputdevice.cpp` | 615-642 | `setCursor()` — stores shape, redundancy check, calls updateCursor |
| `qwaylandinputdevice.cpp` | 633-639 | Redundancy check: if shape unchanged, returns without calling updateCursor |
| `qwaylandinputdevice.cpp` | 153-155 | `Pointer::focusWindow()` — returns `mFocus->waylandWindow()` |
| `qwaylandinputdevice.cpp` | 677 | `mFocus = window->waylandSurface()` — stores QWaylandSurface*, not QWaylandWindow* |
| `quickshell/src/window/proxywindow.cpp` | 101 | `createQQuickWindow()` — returns `new ProxiedWindow(this)` |
| `quickshell/src/wayland/wlr_layershell/surface.cpp` | 91-130 | `LayerSurfaceBridge::init()` — calls `window->create()`, gets waylandWindow via handle() |

### WAYLAND_DEBUG Evidence
```
# All set_shape calls — every serial matches a pointer_enter serial, all shapes = 1
[1771139.991]  -> wp_cursor_shape_device_v1#30.set_shape(256937, 1)  ← enter serial
[1771140.015]  -> wp_cursor_shape_device_v1#30.set_shape(256937, 1)  ← same enter (double call)
[1773677.678]  -> wp_cursor_shape_device_v1#30.set_shape(256941, 1)  ← enter serial
[1777348.582]  -> wp_cursor_shape_device_v1#30.set_shape(256947, 1)  ← enter serial
...10 more, all shape=1, all matching enter serials

# Zero set_shape calls between enter/leave pairs
# (hovering over buttons, text inputs — nothing sent)

# Enter/leave pairs — all on wl_surface#78 (drawers window)
[1771139.964] wl_pointer#29.enter(256937, wl_surface#78, 769, 53)   ← bar area
[1772653.819] wl_pointer#29.leave(256938, wl_surface#78)
[1773677.649] wl_pointer#29.enter(256941, wl_surface#78, 478, 956)  ← bottom area
...
```

### Next Steps
- [ ] **Minimal test case**: User runs `qs -c cursor-test` with `/tmp/quickshell-cursor-test/shell.qml` to confirm the bug reproduces in a clean config (no Symmetria complexity)
- [ ] **Qt Quick cursor debug**: Run with `QT_LOGGING_RULES="qt.quick.hover=true"` or add a debug `onCursorShapeChanged` handler to confirm QML cursor changes fire at item level
- [ ] **GDB breakpoint on changeCursor**: Set breakpoint at `QWaylandCursor::changeCursor` to see if it's called when hovering buttons, and what cursor shape is passed
- [ ] **File upstream bug on Quickshell**: Include WAYLAND_DEBUG trace, minimal reproduction, Qt source analysis. The bug is that cursor shape changes from QML items are never propagated to the Wayland cursor-shape-v1 protocol for layer-shell surfaces

### Open Questions
- Is Qt Quick's `QQuickDeliveryAgent` even tracking hover state for Quickshell's ProxiedWindow? The QML hover effects work (containsMouse, pressed), but cursor delivery may use a separate code path
- Does Quickshell inject mouse events directly into QQuickItems, bypassing QQuickWindow's event() method? If so, cursor updates that depend on QQuickWindow processing the event would never fire
- Could this be a Qt bug rather than Quickshell? If Qt's layer-shell integration doesn't properly wire up cursor propagation, other layer-shell toolkits would be affected too

---

## Pass 3

**Timestamp**: 2026-03-07
**Status**: narrowing (QML hierarchy)

### Findings

**Minimal Quickshell test — plain hierarchy:**
```qml
WlrLayershell {
    Row {
        Rectangle {
            MouseArea { hoverEnabled: true; cursorShape: Qt.PointingHandCursor }  // ✅ WORKS
        }
        TextInput { }  // ❌ I-beam does NOT work
    }
}
```
- **Hand cursor WORKS** on a simple layer-shell surface with no parent MouseArea wrapping
- **I-beam does NOT work** (TextInput) — separate bug, lower priority

**Minimal test — with parent MouseArea (Interactions-like):**
```qml
WlrLayershell {
    MouseArea {
        anchors.fill: parent; hoverEnabled: true
        Row {
            Rectangle {
                MouseArea { hoverEnabled: true; cursorShape: Qt.PointingHandCursor }  // ✅ WORKS
            }
        }
    }
}
```
- Hand cursor STILL works — adding a parent MouseArea with hoverEnabled does NOT break cursor propagation
- **Eliminates** the hypothesis that Interactions MouseArea shadows child cursors

**Symmetria-mimic test — 4-layer hierarchy:**
```qml
WlrLayershell {
    color: "transparent"
    Rectangle { anchors.fill: parent }                           // Layer 1: scrim
    Item { anchors.fill: parent; layer.enabled: true;            // Layer 2: transparency+shadow
           layer.effect: MultiEffect { shadowEnabled: true } }
    MouseArea { anchors.fill: parent; hoverEnabled: true         // Layer 3: Interactions
        Row { Rectangle { MouseArea { cursorShape: ... } } }     // ❌ DOES NOT WORK
    }
    Item { anchors.fill: parent; visible: true                   // Layer 4: Overlay
        MouseArea { anchors.fill: parent; enabled: false }
    }
}
```
- **Hand cursor BREAKS** when the full Symmetria structure is present
- The culprit is one of: `color: "transparent"`, the `layer.enabled: true` Item, the MultiEffect, or the Layer 4 overlay

### Key Insight
This is NOT a platform-level Quickshell/Qt/Wayland bug. Cursor shapes DO work on layer-shell surfaces. The issue is caused by a specific combination of QML elements in Symmetria's Drawers.qml hierarchy that prevents Qt Quick's cursor propagation from reaching the platform layer.

### Updated Hypotheses
| # | Hypothesis | Confidence | Evidence |
|---|-----------|------------|----------|
| 7 | `Item { layer.enabled: true; layer.effect: MultiEffect }` as a sibling covering the full window interferes with Qt Quick's cursor hit-testing or propagation. When `layer.enabled` creates an FBO, it may alter item tree traversal for cursor resolution | HIGH | The 4-layer test breaks cursor; the only new elements vs the 2-layer test are the `layer.enabled` Item, MultiEffect, the transparent color, and the overlay Item |
| 8 | The combination of `color: "transparent"` on the window + multiple full-window siblings creates an item stacking issue where cursor resolution picks the wrong item | MED | Transparency changes how the window surface is composited |
| 9 | The overlay Item (Layer 4, `visible: true` with disabled MouseArea) blocks cursor resolution even when disabled because Qt Quick's hit-testing still considers visible items in z-order | MED | The overlay sits on top of everything and is always visible |

### Eliminated
- **Interactions MouseArea shadows child cursors**: ELIMINATED — minimal test with parent MouseArea wrapping children still shows hand cursor correctly
- **Platform-level layer-shell cursor bug**: ELIMINATED — cursors DO work on Quickshell layer-shell surfaces in a simple hierarchy
- **I-beam on TextInput**: Separate bug (doesn't work even in the simplest test case). Likely a Quickshell/Qt issue with TextInput cursor specifically. Low priority.

### Next Steps
- [ ] **Binary search the 4-layer test**: Remove elements one at a time to find exactly which layer breaks cursor propagation:
  - Test A: Remove Layer 4 (overlay) → does cursor work?
  - Test B: Remove Layer 2 (layer.enabled + MultiEffect) → does cursor work?
  - Test C: Change window color from "transparent" to "#2d2d2d" → does cursor work?
- [ ] **If `layer.enabled` is the culprit**: Test whether `layer.enabled: true` on ANY sibling Item breaks cursor for MouseAreas in other siblings. File Qt bug if confirmed
- [ ] **If overlay is the culprit**: Fix by setting `visible: false` instead of relying on `dialogScale > 0` when KeyChords is inactive
- [ ] **Apply fix in Symmetria**: Once the breaking element is identified, modify Drawers.qml or the offending component

### Open Questions
- Does `layer.enabled: true` on a sibling Item affect Qt Quick's cursor resolution for other siblings? This would be a Qt Quick bug
- Does a disabled but visible MouseArea in a higher z-order sibling block cursor resolution for lower siblings?
- Is `color: "transparent"` on the WlrLayershell significant? The first minimal test used `color: "#2d2d2d"`

---

## Pass 4

**Timestamp**: 2026-03-08
**Status**: resolved

### Findings

**Binary search results** (user-tested each variant):

| Test | Config | Cursor Works? | Conclusion |
|------|--------|---------------|------------|
| A: Remove overlay (Layer 4) | Layers 1+2+3 only | **Yes** | **Overlay is the culprit** |
| B: Remove layer.enabled (Layer 2) | Layers 1+3+4 | No | layer.enabled is not the issue |
| C: Opaque window color | All 4 layers, color: "#2d2d2d" | No | Transparency is not the issue |

**Root cause confirmed**: The overlay Item (`modules/keychords/Overlay.qml`) used `dialogScale: shouldShow ? 1.0 : 0.01`, making `visible: dialogScale > 0` always true. Its full-window dismiss `MouseArea` (with `enabled: false`) sat at the highest z-order in `Drawers.qml:236`. Qt Quick's cursor hit-testing considers visible MouseAreas regardless of `enabled` state — the overlay's default ArrowCursor was found first, shadowing all `cursorShape` settings below.

### Fix Applied

Changed `dialogScale` idle value from `0.01` to `0.0` in `modules/keychords/Overlay.qml:30`:
- When idle: `dialogScale = 0.0` → `visible: 0.0 > 0` → `false` → overlay removed from cursor hit-testing
- Close animation: scale passes through positive values → `visible: true` during animation → `visible: false` at completion
- Added explanatory comment documenting the constraint

Also added `hoverEnabled: true` and `cursorShape: Qt.PointingHandCursor` to three bar components with inline MouseAreas: `TrayItem.qml`, `Workspace.qml`, `SpecialWorkspaces.qml`.

### Eliminated
- **Hypothesis #7 (layer.enabled + MultiEffect)**: ELIMINATED — Test B removed Layer 2 but cursor still broken
- **Hypothesis #8 (transparent window color)**: ELIMINATED — Test C used opaque color but cursor still broken
- **Hypothesis #9 (overlay Item with disabled MouseArea)**: CONFIRMED — Test A removed the overlay and cursor worked

### Resolved
All pointer cursors now appear correctly on buttons, tray items, workspace indicators, and special workspace items. The `Easing.OutBack` overshoot below 0 on close animation is safe because `visible: dialogScale > 0` removes the item from rendering before sub-zero frames occur.
