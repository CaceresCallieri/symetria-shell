# Cursor Shape Broken on Layer-Shell Surfaces

## Problem

Mouse cursor stayed as the default arrow on ALL clickable elements in the Symmetria shell — buttons, tray items, workspace indicators, text inputs. Hover effects (ripple, color changes) and click events worked correctly, but the cursor never changed to `PointingHandCursor` or any other shape. Regular Qt QML windows (xdg-shell) showed correct cursors, making this appear to be a layer-shell or Quickshell platform bug.

## Root Cause

A **visible but disabled full-window `MouseArea`** in the KeyChords overlay (`modules/keychords/Overlay.qml:53`) was shadowing cursor resolution for the entire drawers window.

The overlay used `dialogScale: shouldShow ? 1.0 : 0.01` with `visible: dialogScale > 0`. Since `0.01 > 0`, the overlay Item was **always visible**, even when KeyChords was inactive. Its full-window dismiss `MouseArea` (with `enabled: false`) sat at the highest z-order in `Drawers.qml` (line 236).

**Qt Quick's cursor resolution** (`QQuickWindowPrivate::updateCursor`) walks the visual item tree **top-down by z-order**. A `MouseArea` that is `visible: true` participates in cursor hit-testing **regardless of its `enabled` state**. The disabled overlay MouseArea's default `ArrowCursor` was found first, and the search never reached the button `PointingHandCursor` underneath.

**Key chain**: `visible: true` + `enabled: false` + highest z-order + default ArrowCursor → cursor resolution stops here → all items below never get their cursor applied → `wp_cursor_shape_device_v1.set_shape()` is never called with non-default shapes.

## Solution

Changed the idle `dialogScale` target from `0.01` to `0.0` in `modules/keychords/Overlay.qml:30`:

```qml
// Before (broken):
property real dialogScale: shouldShow ? 1.0 : 0.01  // visible: 0.01 > 0 → true (always)

// After (fixed):
property real dialogScale: shouldShow ? 1.0 : 0.0    // visible: 0.0 > 0 → false (when idle)
```

When `shouldShow` is false, `dialogScale` animates to `0.0`, making `visible: dialogScale > 0` evaluate to `false`. The overlay and its MouseArea are removed from cursor hit-testing. The close animation still works because `dialogScale` passes through positive values on its way to `0.0`, keeping the item visible during the animation. The `Easing.OutBack` overshoot below 0 is imperceptible at near-zero scale.

## Key Findings

- **Cursor shapes DO work on Quickshell layer-shell surfaces** — confirmed via minimal test case. This was NOT a platform bug
- **`enabled: false` on a MouseArea does NOT prevent it from participating in cursor resolution** — only `visible: false` removes it from cursor hit-testing
- **WAYLAND_DEBUG trace** confirmed: all `wp_cursor_shape_device_v1.set_shape()` calls used shape=1 (default arrow) and occurred only on `pointer_enter` events — zero cursor changes between enter/leave pairs
- The Wayland cursor-shape-v1 protocol pipeline works correctly: `QWaylandCursorShape` binds successfully, `set_shape` calls are transmitted, the compositor applies them. The failure was purely in Qt Quick's item-level cursor resolution never finding the correct cursor to propagate
- **TextInput I-beam cursor** is a separate, unrelated bug — doesn't work even in the simplest Quickshell test case (low priority)

## Binary Search Results

| Test | Config | Cursor Works? | Conclusion |
|------|--------|---------------|------------|
| Baseline | Simple MouseArea with cursorShape | Yes | Layer-shell cursors work |
| + Parent MouseArea | Added full-window parent (like Interactions) | Yes | Parent MouseArea doesn't shadow children |
| + All 4 layers | Full Symmetria mimic | **No** | Something in the hierarchy breaks it |
| A: Remove overlay (Layer 4) | Layers 1+2+3 only | **Yes** | **Overlay is the culprit** |
| B: Remove layer.enabled (Layer 2) | Layers 1+3+4 | No | layer.enabled is not the issue |
| C: Opaque window color | All 4 layers, color: "#2d2d2d" | No | Transparency is not the issue |

## Affected Components

| Component | File | Impact |
|-----------|------|--------|
| KeyChords Overlay | `modules/keychords/Overlay.qml:30` | **Root cause** — `dialogScale` idle value changed from 0.01 to 0.0 |
| Drawers window | `modules/drawers/Drawers.qml:236-239` | Overlay's parent — z-order context |
| StateLayer | `components/StateLayer.qml:20` | Already had correct `cursorShape: Qt.PointingHandCursor` — was being shadowed |
| TrayItem | `modules/bar/components/TrayItem.qml:10` | Added `cursorShape: Qt.PointingHandCursor` (now works) |
| Workspace | `modules/bar/components/workspaces/Workspace.qml:69` | Added `cursorShape: Qt.PointingHandCursor` (now works) |
| SpecialWorkspaces | `modules/bar/components/workspaces/SpecialWorkspaces.qml:238` | Added `cursorShape: Qt.PointingHandCursor` (now works) |

## Prevention

- **Never use a non-zero idle value for scale-driven visibility** when the component contains a full-window MouseArea. Use `0.0` so `visible: scale > 0` becomes `false` when idle
- **Full-window MouseAreas MUST be guarded with `visible: <condition>`**, not just `enabled: <condition>`. Qt Quick's cursor resolution checks visibility, not enabled state, when walking the item tree
- **When adding overlay components to Drawers.qml**: verify that their idle state has `visible: false`. Any always-visible sibling with a MouseArea at higher z-order will shadow all cursors below
- **Test cursor behavior after adding new overlay-pattern components**: hover over a button to verify the pointer cursor still appears
