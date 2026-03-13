# Drawer & Bar Extension Guide

Procedural knowledge for adding new panels, pill containers, and focus management to the shell.

## Panel Backgrounds (Union Corners)

The drawer system uses `ShapePath` components to render panel backgrounds with "union" corner effects — smooth visual connections between panels and the shell border/bar.

### Reusable Components (`components/shapes/`)

| Component | Purpose | Union Corners |
|-----------|---------|---------------|
| `TopHangingBackground` | Panels hanging from bar/top | TL, TR |
| `BottomUpBackground` | Panels rising from bottom | BL, BR |

Edge-case panels (Sidebar, Notifications, Utilities) have inter-panel dependencies and use custom implementations in `modules/drawers/Backgrounds.qml`.

### Standard startX/startY Patterns

| Orientation | startX | startY |
|-------------|--------|--------|
| Top-hanging, centered | `(shape.width - wrapper.width) / 2 - rounding` | `0` |
| Bottom-up, centered | `(shape.width - wrapper.width) / 2 - rounding` | `shape.height` |
| Bottom-up, left-aligned | `rounding` | `shape.height` |
| Top-hanging, positioned | `wrapper.x - rounding` | `wrapper.y` |

### Creating a New Panel Background

1. **Identify panel orientation:** top-hanging or bottom-up?
2. **Choose component:** `TopHangingBackground` or `BottomUpBackground`
3. **Add ShapePath in `Backgrounds.qml`:** Set `wrapper`, `startX`, `startY` using the `rounding` read-only property

Both components include adaptive `roundingY` to prevent rendering artifacts when panel height < rounding × 2.

---

## Bar Pill Pattern

Bar components are grouped into glassmorphism "pill" containers. See `modules/bar/components/PillContainer.qml` for the base component (well-documented inline).

### Current Pills

| Component | Contents | Color | Popouts |
|-----------|----------|-------|---------|
| `StatusIcons.qml` | Audio, Network, Bluetooth, Battery | m3secondary | Yes |
| `Tray.qml` | System tray items | m3surfaceContainerHigh | Yes |
| `TimePill.qml` | Clock, Date | m3tertiary | Planned |
| `SystemPill.qml` | CPU, RAM, Updates | m3tertiary | No |

Note: `Tray.qml` doesn't use PillContainer due to unique requirements (conditional styling, compact mode, expand/collapse).

### Creating a New Pill

1. Extend `PillContainer` — set `colour`, `iconContainer` (optional), `visible` binding
2. Add `RowLayout` with padding spacers and `PillContainer.WrappedLoader` children
3. Register in `Bar.qml`: add to `hasPillMargins`, switch case, and Component definition

---

## Focus Management in Drawers

Keyboard-interactive drawers use `FocusManager` (`components/misc/FocusManager.qml`) to handle focus-on-open and prevent focus-stealing during Loader pre-loading. The component has comprehensive inline documentation.

### Quick Reference

```qml
import qs.components.misc

FocusManager {
    active: root.visibilities.drawerName  // Bind to drawer visibility
    target: focusTarget                    // Element to focus when opened
    onClose: () => focusTarget.text = ""   // Optional cleanup
}
```

For tab-dependent focus, use a conditional target binding:
```qml
FocusManager {
    active: root.visibilities.clipboard
    target: currentTab === 0 ? search : imageNavFocus
}
```

### Current Implementations

| Module | Focus Target | Notes |
|--------|--------------|-------|
| Launcher | Search TextField | `onClose` clears text |
| Clipboard | Search or ImageNavFocus | Dynamic target based on tab |
| Askpass | Dialog container | Simple usage |
| Session | Logout button | Simple usage |
