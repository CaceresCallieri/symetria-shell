# Corner Union Effects and Border Rendering

This document explains the architecture behind the shell's rounded border corners, the "union effect" pattern, and how to avoid transparency overlap artifacts.

## Overview

The Caelestia shell uses a two-layer system for rendering the border frame and panel backgrounds:

1. **Border.qml** - Renders the outer border frame using an inverted mask
2. **Backgrounds.qml** - Contains ShapePath components for each panel's background

When transparency is enabled, both layers are composited together. If they overlap, visual artifacts appear (darker regions where both layers fill the same pixels).

## Architecture

### Border.qml

The Border uses a `Rectangle` mask with `radius` to create rounded corners. The mask is **inverted**, meaning the `StyledRect` fills everywhere the mask IS NOT - creating the border frame around the content area.

```qml
StyledRect {
    layer.effect: MultiEffect {
        maskSource: mask
        maskInverted: true  // Key: inverts the mask
    }
}

Rectangle {
    // This defines the content area hole
    radius: Config.border.rounding
    // Per-corner radii available:
    topLeftRadius: Config.border.rounding
    topRightRadius: 0  // Let Backgrounds handle this
    bottomLeftRadius: Config.border.rounding
    bottomRightRadius: 0  // Let Backgrounds handle this
}
```

### Backgrounds.qml

A `Shape` containing multiple `ShapePath` components, one for each panel:
- Dashboard.Background (left side)
- Notifications.Background (top-right)
- Utilities.Background (bottom-right)
- Sidebar.Background (right side, between notifications and utilities)
- Launcher.Background (bottom center)
- etc.

Each ShapePath draws a closed path defining its panel's filled region.

## The Union Effect

A "union effect" is a smooth curved transition where a panel meets the border. Instead of a sharp corner, the panel's edge curves outward to fill the border's rounded corner space.

### How It Works

1. The Border has rounded corners that create small "quadrant" cutouts at each corner
2. Panel ShapePaths extend INTO these quadrants with matching arcs
3. The arc "fills" the quadrant, creating a seamless visual union

### PathArc Direction

The arc direction determines which way it curves:

- **`PathArc.Counterclockwise`** - Arc curves **OUTWARD** (away from shape center)
  - Used for union effects where panel meets border
  - Creates the characteristic "bulge" into the corner

- **`PathArc.Clockwise`** (default) - Arc curves **INWARD** (toward shape center)
  - Used for regular panel corners
  - Creates standard rounded corners within the panel

### Example: Dashboard BL Corner Union

```qml
// Dashboard draws clockwise from (0,0)
// At bottom-left, approaching the corner:

PathLine {
    relativeX: 0
    relativeY: root.wrapper.height - root.roundingY  // Stop before corner
}

// Union arc: curves outward into border's BL corner
PathArc {
    relativeX: root.rounding
    relativeY: root.roundingY
    radiusX: root.rounding
    radiusY: Math.min(root.rounding, root.wrapper.height)
    direction: PathArc.Counterclockwise  // OUTWARD curve
}
```

## The Transparency Overlap Problem

### Symptom

When transparency is enabled, certain corners appear darker than the rest of the border.

### Cause

Both Border AND a panel's ShapePath fill the same corner region. With transparency:
1. Border renders the corner with alpha
2. ShapePath renders the same corner with alpha
3. Compositor blends them = double alpha = darker appearance

### Solution: Exclusive Ownership

Each corner region must be filled by **exactly one** component:

| Corner | Filled By | Method |
|--------|-----------|--------|
| Top-Left (TL) | Border | `topLeftRadius: rounding` |
| Bottom-Left (BL) | Border | `bottomLeftRadius: rounding` |
| Top-Right (TR) | Notifications.Background | Union arc in ShapePath |
| Bottom-Right (BR) | Utilities.Background | Union arc in ShapePath |

### Implementation

**Border.qml** - Disable right-side corner rounding:
```qml
Rectangle {
    topLeftRadius: Config.border.rounding
    topRightRadius: 0  // Backgrounds handles TR
    bottomLeftRadius: Config.border.rounding
    bottomRightRadius: 0  // Backgrounds handles BR
}
```

**Notifications/Utilities Background.qml** - Add corner union arcs:
```qml
// Start path INSIDE the corner (at width - rounding, not width)
startX: root.width - rounding

// Path draws around panel, then returns via corner union:
PathArc {
    relativeX: -root.rounding
    relativeY: -root.rounding  // or +rounding for BR
    radiusX: root.rounding
    radiusY: Math.min(root.rounding, root.wrapper.height)
    direction: PathArc.Counterclockwise
}
```

## Key Implementation Details

### Starting Position

For panels with corner unions, start the path **inside** the corner:
```qml
startX: root.width - rounding  // Not root.width
startY: 0  // or root.height for bottom panels
```

This allows the path to draw around the panel and return to the start via a corner union arc.

### Height Clamping

Always clamp arc radii to prevent rendering issues when panels are collapsed:
```qml
radiusY: Math.min(root.rounding, root.wrapper.height)
```

### Path Closure

ShapePaths auto-close from the last point back to the start. Design paths so:
1. The corner union arc is the LAST element
2. The arc ends exactly at the start point
3. Auto-close is zero-length (no additional line drawn)

### Avoid Overlapping Right Edge

When Notifications/Utilities draw union arcs, ensure their paths don't extend through the Sidebar's region. Each shape should only fill its own panel area plus its corner union.

## Debugging Tips

1. **Temporarily disable transparency** to see if overlap is the issue
2. **Use different fill colors** for each ShapePath to visualize overlaps
3. **Trace path coordinates** manually to verify geometry
4. **Check arc directions** - Counterclockwise for unions, Clockwise for internal corners

## File Reference

| File | Purpose |
|------|---------|
| `modules/drawers/Border.qml` | Border frame with per-corner radii |
| `modules/drawers/Backgrounds.qml` | Shape containing all panel ShapePaths |
| `modules/dashboard/Background.qml` | Left-side panel with BL/BR unions |
| `modules/notifications/Background.qml` | Top-right panel with TR union |
| `modules/utilities/Background.qml` | Bottom-right panel with BL union, squared BR |
| `modules/sidebar/Background.qml` | Right-side connector (no corner unions) |
| `config/BorderConfig.qml` | Configuration for border.rounding, border.thickness |

## Squared Corners

Sometimes a squared (90°) corner is preferable to a union arc. This is useful when:
- The union arc geometry doesn't align properly with the border
- A simpler, cleaner visual is desired
- The corner doesn't need to fill a border's rounded cutout

### How to Create a Squared Corner

Instead of using a `PathArc` to curve around the corner, extend the line past where the arc would begin and let the path auto-close:

```qml
// BEFORE: Rounded BR corner with union arc
PathLine {
    relativeX: 0
    relativeY: root.wrapper.height  // Stop at (width, height - rounding)
}
PathArc {
    relativeX: -root.rounding
    relativeY: root.rounding
    radiusX: root.rounding
    radiusY: root.rounding
}

// AFTER: Squared BR corner
PathLine {
    relativeX: 0
    relativeY: root.wrapper.height + root.rounding  // Extend to (width, height)
}
// Path auto-closes with horizontal line to start point
// This creates a 90° squared corner
```

### Current Corner Configuration

| Panel | Corner | Type | Reason |
|-------|--------|------|--------|
| Dashboard | BL | Union arc | Fills border's rounded BL corner |
| Notifications | TR | Union arc | Fills border's rounded TR corner |
| Utilities | BL | Union arc | Creates smooth transition at bottom edge |
| Utilities | BR | **Squared** | Simpler geometry, avoids fill direction issues |

### Why Utilities BR is Squared

The utilities BR corner was changed from a union arc to squared because:
1. The union arc created a visual gap when the utilities popout was triggered
2. Arc fill direction ambiguity caused rendering artifacts
3. A squared corner provides clean, predictable geometry at the shell's absolute bottom-right

## Summary

The corner union system requires careful coordination between Border and Backgrounds:

1. **Border** owns left corners (rounded via Rectangle radii)
2. **Backgrounds** own right corners (filled via ShapePath union arcs or squared)
3. **No overlap** = no transparency artifacts
4. **Counterclockwise** arcs curve outward for union effects
5. **Height clamping** handles edge cases when panels collapse
6. **Squared corners** are an alternative when union arcs cause issues
