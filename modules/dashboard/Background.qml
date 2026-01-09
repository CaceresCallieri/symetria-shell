import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Shapes

ShapePath {
    id: root

    required property Wrapper wrapper
    readonly property real rounding: Config.border.rounding
    readonly property bool flatten: wrapper.height < rounding * 2
    readonly property real roundingY: flatten ? wrapper.height / 2 : rounding

    strokeWidth: -1
    fillColor: Colours.generalBackground

    // Left-edge panel: straight left side, original rounded right side
    // Start at top-left (0, 0), draw clockwise

    // Line 1: Down the left edge (stop before BL corner arc)
    PathLine {
        relativeX: 0
        relativeY: root.wrapper.height - root.roundingY
    }

    // Arc: Bottom-left corner (union effect - curves outward into shell)
    PathArc {
        relativeX: root.rounding
        relativeY: root.roundingY
        radiusX: root.rounding
        radiusY: Math.min(root.rounding, root.wrapper.height)
        direction: PathArc.Counterclockwise
    }

    // Line 2: Right along the bottom edge (stop before BR corner arc)
    PathLine {
        relativeX: root.wrapper.width - root.rounding * 2
        relativeY: 0
    }

    // Arc 1: Bottom-right corner (original parameters)
    PathArc {
        relativeX: root.rounding
        relativeY: -root.roundingY
        radiusX: root.rounding
        radiusY: Math.min(root.rounding, root.wrapper.height)
        direction: PathArc.Counterclockwise
    }

    // Line 3: Up the right edge
    PathLine {
        relativeX: 0
        relativeY: -(root.wrapper.height - root.roundingY * 2)
    }

    // Arc 2: Top-right corner (original parameters)
    PathArc {
        relativeX: root.rounding
        relativeY: -root.roundingY
        radiusX: root.rounding
        radiusY: Math.min(root.rounding, root.wrapper.height)
    }

    // Auto-closes back to (0, 0) along top edge

    Behavior on fillColor {
        CAnim {}
    }
}
