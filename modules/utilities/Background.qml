import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Shapes

ShapePath {
    id: root

    required property Wrapper wrapper
    required property var sidebar
    readonly property real rounding: Config.border.rounding
    readonly property bool flatten: wrapper.height < rounding * 2
    readonly property real roundingY: flatten ? wrapper.height / 2 : rounding

    strokeWidth: -1
    fillColor: Colours.generalBackgroundOpaque

    // Path drawing: Counterclockwise arcs curve OUTWARD (union with border/panels)
    // Start at (width - rounding, height), draw around panel, return via BR corner union

    // Line 1: Left along bottom edge to (width - rounding - wrapper.width, height)
    PathLine {
        relativeX: -root.wrapper.width
        relativeY: 0
    }

    // Arc: BL corner - union (curves outward into border)
    PathArc {
        relativeX: root.rounding
        relativeY: -root.roundingY
        radiusX: root.rounding
        radiusY: Math.min(root.rounding, root.wrapper.height)
        direction: PathArc.Counterclockwise
    }

    // Line 2: Up the left edge
    PathLine {
        relativeX: 0
        relativeY: -(root.wrapper.height - root.roundingY * 2)
    }

    // Arc: TL corner - connecting to sidebar
    PathArc {
        relativeX: root.sidebar.utilsRoundingX
        relativeY: -root.roundingY
        radiusX: root.sidebar.utilsRoundingX
        radiusY: Math.min(root.rounding, root.wrapper.height)
    }

    // Line 3: Right along top edge
    PathLine {
        relativeX: root.wrapper.height > 0 ? root.wrapper.width - root.rounding - root.sidebar.utilsRoundingX : root.wrapper.width
        relativeY: 0
    }

    // Arc: TR corner going into sidebar
    PathArc {
        relativeX: root.rounding
        relativeY: -root.rounding
        radiusX: root.rounding
        radiusY: root.rounding
        direction: PathArc.Counterclockwise
    }

    // Line 4: Down the right edge to bottom
    PathLine {
        relativeX: 0
        relativeY: root.wrapper.height + root.rounding
    }

    // Path auto-closes with horizontal line from (width, height) to start at (width - rounding, height)
    // This creates a squared BR corner

    Behavior on fillColor {
        CAnim {}
    }
}
