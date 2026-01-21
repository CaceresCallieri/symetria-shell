import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Shapes

/// Reusable ShapePath for top-hanging panels (bar popouts, askpass, session, OSD).
///
/// Renders a panel background with union corners at top (TL, TR) that blend
/// smoothly with the bar/border, and standard rounded corners at bottom (BL, BR).
///
/// ## Positioning
/// Parent Shape must set `startX`/`startY` to position the path:
/// - **Centered panels:** `startX: (shape.width - wrapper.width) / 2 - rounding`
/// - **Top-hanging:** `startY: 0` (starts at top-left before TL arc)
///
/// ## Example
/// ```qml
/// import qs.components.shapes
///
/// TopHangingBackground {
///     wrapper: root.panels.askpass
///     startX: (shape.width - wrapper.width) / 2 - rounding
///     startY: 0
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
    readonly property real roundingY: wrapper.height < rounding * 2 ? wrapper.height / 2 : rounding

    strokeWidth: -1
    fillColor: customFillColor

    // Arc 1: Top-left corner (union - curves outward into bar/border)
    PathArc {
        relativeX: root.rounding
        relativeY: root.roundingY
        radiusX: root.rounding
        radiusY: root.roundingY
    }

    // Line 1: Left edge (going down)
    PathLine {
        relativeX: 0
        relativeY: root.wrapper.height - root.roundingY * 2
    }

    // Arc 2: Bottom-left corner (standard - curves inward)
    PathArc {
        relativeX: root.rounding
        relativeY: root.roundingY
        radiusX: root.rounding
        radiusY: root.roundingY
        direction: PathArc.Counterclockwise
    }

    // Line 2: Bottom edge (going right)
    PathLine {
        relativeX: root.wrapper.width - root.rounding * 2
        relativeY: 0
    }

    // Arc 3: Bottom-right corner (standard - curves inward)
    PathArc {
        relativeX: root.rounding
        relativeY: -root.roundingY
        radiusX: root.rounding
        radiusY: root.roundingY
        direction: PathArc.Counterclockwise
    }

    // Line 3: Right edge (going up)
    PathLine {
        relativeX: 0
        relativeY: -(root.wrapper.height - root.roundingY * 2)
    }

    // Arc 4: Top-right corner (union - curves outward into bar/border)
    PathArc {
        relativeX: root.rounding
        relativeY: -root.roundingY
        radiusX: root.rounding
        radiusY: root.roundingY
    }

    // Top edge auto-closes back to start

    Behavior on fillColor {
        CAnim {}
    }
}
