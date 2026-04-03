import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Shapes

/// Reusable ShapePath for bottom-up panels (launcher, clipboard).
///
/// Renders a panel background with union corners at bottom (BL, BR) that blend
/// smoothly with the border, and standard rounded corners at top (TL, TR).
///
/// ## Positioning
/// Parent Shape must set `startX`/`startY` to position the path:
/// - **Centered panels:** `startX: (shape.width - wrapper.width) / 2 - rounding`
/// - **Bottom-up:** `startY: shape.height` (starts at bottom-left before BL arc)
///
/// ## Example
/// ```qml
/// import qs.components.shapes
///
/// BottomUpBackground {
///     wrapper: root.panels.launcher
///     startX: (shape.width - wrapper.width) / 2 - rounding
///     startY: shape.height
/// }
/// ```
ShapePath {
    id: root

    /// The wrapper Item providing width/height for the panel.
    /// Must have `width` and `height` properties (typically a module's Wrapper.qml).
    required property Item wrapper

    /// Custom rounding radius. When >= 0, overrides Config.border.rounding.
    /// Use for special cases like bar popouts' attached/detached modes:
    /// `customRounding: wrapper.isDetached ? Appearance.rounding.normal : Config.border.rounding`
    property real customRounding: -1

    /// Custom fill color. Defaults to Colours.generalBackgroundOpaque.
    /// Color changes are automatically animated via CAnim Behavior.
    property color customFillColor: Colours.generalBackgroundOpaque

    /// Computed rounding value (for parent to calculate startX/startY).
    readonly property real rounding: customRounding >= 0 ? customRounding : Config.border.rounding

    /// Adaptive Y-radius to prevent rendering artifacts on short panels.
    readonly property real roundingY: {
        const h = wrapper?.height ?? 0;
        return h < rounding * 2 ? h / 2 : rounding;
    }

    // Safe accessors for wrapper dimensions (null-safe)
    readonly property real _wrapperHeight: wrapper?.height ?? 0
    readonly property real _wrapperWidth: wrapper?.width ?? 0

    strokeWidth: -1
    fillColor: customFillColor

    // Arc 1: Bottom-left corner (union - curves outward into border)
    PathArc {
        relativeX: root.rounding
        relativeY: -root.roundingY
        radiusX: root.rounding
        radiusY: root.roundingY
        direction: PathArc.Counterclockwise
    }

    // Line 1: Left edge (going up)
    PathLine {
        relativeX: 0
        relativeY: -(root._wrapperHeight - root.roundingY * 2)
    }

    // Arc 2: Top-left corner (standard - curves inward)
    PathArc {
        relativeX: root.rounding
        relativeY: -root.roundingY
        radiusX: root.rounding
        radiusY: root.roundingY
    }

    // Line 2: Top edge (going right)
    PathLine {
        relativeX: root._wrapperWidth - root.rounding * 2
        relativeY: 0
    }

    // Arc 3: Top-right corner (standard - curves inward)
    PathArc {
        relativeX: root.rounding
        relativeY: root.roundingY
        radiusX: root.rounding
        radiusY: root.roundingY
    }

    // Line 3: Right edge (going down)
    PathLine {
        relativeX: 0
        relativeY: root._wrapperHeight - root.roundingY * 2
    }

    // Arc 4: Bottom-right corner (union - curves outward into border)
    PathArc {
        relativeX: root.rounding
        relativeY: root.roundingY
        radiusX: root.rounding
        radiusY: root.roundingY
        direction: PathArc.Counterclockwise
    }

    // Bottom edge auto-closes back to start

    Behavior on fillColor {
        CAnim {}
    }
}
