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
    fillColor: Colours.generalBackground

    // Path drawing: Counterclockwise arcs curve OUTWARD (union with border/panels)
    // Start at (width - rounding, 0), draw around panel, return via TR corner union

    // Line 1: Left along top edge to (width - rounding - wrapper.width, 0)
    PathLine {
        relativeX: -root.wrapper.width
        relativeY: 0
    }

    // Arc: TL corner of notifications (curves into panel)
    PathArc {
        relativeX: root.rounding
        relativeY: root.roundingY
        radiusX: root.rounding
        radiusY: Math.min(root.rounding, root.wrapper.height)
    }

    // Line 2: Down the left edge
    PathLine {
        relativeX: 0
        relativeY: root.wrapper.height - root.roundingY * 2
    }

    // Arc: BL corner - union with sidebar (curves outward)
    PathArc {
        relativeX: root.sidebar.notifsRoundingX
        relativeY: root.roundingY
        radiusX: root.sidebar.notifsRoundingX
        radiusY: Math.min(root.rounding, root.wrapper.height)
        direction: PathArc.Counterclockwise
    }

    // Line 3: Right along bottom edge
    PathLine {
        relativeX: root.wrapper.height > 0 ? root.wrapper.width - root.rounding - root.sidebar.notifsRoundingX : root.wrapper.width
        relativeY: 0
    }

    // Arc: BR corner going into sidebar
    PathArc {
        relativeX: root.rounding
        relativeY: root.rounding
        radiusX: root.rounding
        radiusY: root.rounding
    }

    // Line 4: Up the right edge to TR corner
    PathLine {
        relativeX: 0
        relativeY: -root.wrapper.height
    }

    // Arc: TR corner union (curves outward into border corner)
    PathArc {
        relativeX: -root.rounding
        relativeY: -root.rounding
        radiusX: root.rounding
        radiusY: Math.min(root.rounding, root.wrapper.height)
        direction: PathArc.Counterclockwise
    }

    // Path closes back to start at (width - rounding, 0)

    Behavior on fillColor {
        CAnim {}
    }
}
