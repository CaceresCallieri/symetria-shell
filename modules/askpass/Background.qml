import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Shapes

ShapePath {
    id: root

    required property Wrapper wrapper
    readonly property real rounding: Config.border.rounding
    // Null-safe height/width access for initial render pass
    readonly property real wrapperHeight: wrapper?.height ?? 0
    readonly property real wrapperWidth: wrapper?.width ?? 0
    readonly property bool flatten: wrapperHeight < rounding * 2
    readonly property real roundingY: flatten ? wrapperHeight / 2 : rounding

    strokeWidth: -1
    fillColor: Colours.generalBackgroundOpaque

    // Top-center panel: start at left edge of top union arc zone
    // Path: TL union arc → down left edge → BL corner → across bottom → BR corner → up right edge → TR union arc → close

    // Arc: Top-left corner (outward union curve - connects to bar/border)
    PathArc {
        relativeX: -root.rounding
        relativeY: root.roundingY
        radiusX: root.rounding
        radiusY: Math.min(root.rounding, root.wrapperHeight)
        direction: PathArc.Counterclockwise
    }

    // Line: Down the left edge (stop before BL corner arc)
    PathLine {
        relativeX: 0
        relativeY: root.wrapperHeight - root.roundingY * 2
    }

    // Arc: Bottom-left corner (standard rounded corner - curves inward)
    PathArc {
        relativeX: root.rounding
        relativeY: root.roundingY
        radiusX: root.rounding
        radiusY: Math.min(root.rounding, root.wrapperHeight)
    }

    // Line: Right along the bottom edge
    PathLine {
        relativeX: root.wrapperWidth - root.rounding * 2
        relativeY: 0
    }

    // Arc: Bottom-right corner (standard rounded corner - curves inward)
    PathArc {
        relativeX: root.rounding
        relativeY: -root.roundingY
        radiusX: root.rounding
        radiusY: Math.min(root.rounding, root.wrapperHeight)
    }

    // Line: Up the right edge
    PathLine {
        relativeX: 0
        relativeY: -(root.wrapperHeight - root.roundingY * 2)
    }

    // Arc: Top-right corner (outward union curve - connects to bar/border)
    PathArc {
        relativeX: root.rounding
        relativeY: -root.roundingY
        radiusX: root.rounding
        radiusY: Math.min(root.rounding, root.wrapperHeight)
        direction: PathArc.Counterclockwise
    }

    // Path auto-closes along top edge back to start

    Behavior on fillColor {
        CAnim {}
    }
}
