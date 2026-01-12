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
    fillColor: Colours.generalBackgroundOpaque

    // Left-edge panel: start at (rounding, 0) with rounded TL corner (outward/union)
    // Path: TL arc → down left edge → BL arc → right → BR arc → up → TR arc → close

    // Arc: Top-left corner (outward curve - union effect like BL)
    PathArc {
        relativeX: -root.rounding
        relativeY: root.roundingY
        radiusX: root.rounding
        radiusY: Math.min(root.rounding, root.wrapper.height)
        direction: PathArc.Counterclockwise
    }

    // Line 1: Down the left edge (stop before BL corner arc)
    PathLine {
        relativeX: 0
        relativeY: root.wrapper.height - root.roundingY * 2
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

    // Arc: Bottom-right corner (outward curve)
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

    // Arc: Top-right corner (inward curve - standard rounded corner, not a union)
    PathArc {
        relativeX: root.rounding
        relativeY: -root.roundingY
        radiusX: root.rounding
        radiusY: Math.min(root.rounding, root.wrapper.height)
    }

    // Path auto-closes along top edge back to start at (rounding, 0)

    Behavior on fillColor {
        CAnim {}
    }
}
