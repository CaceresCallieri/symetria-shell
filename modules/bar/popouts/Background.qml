import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Shapes

ShapePath {
    id: root

    required property Wrapper wrapper
    readonly property real rounding: wrapper.isDetached ? Appearance.rounding.normal : Config.border.rounding
    readonly property bool flatten: wrapper.height < rounding * 2
    readonly property real roundingY: flatten ? wrapper.height / 2 : rounding

    strokeWidth: -1
    fillColor: Colours.palette.m3surface

    // Arc 1: Top-left corner
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

    // Arc 2: Bottom-left corner
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

    // Arc 3: Bottom-right corner
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

    // Arc 4: Top-right corner
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
