import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Shapes

ShapePath {
    id: root

    required property Wrapper wrapper
    required property var panels

    readonly property real rounding: Config.border.rounding

    readonly property real utilsWidthDiff: panels.utilities.width - wrapper.width
    readonly property real utilsRoundingX: utilsWidthDiff < rounding * 2 ? utilsWidthDiff / 2 : rounding

    strokeWidth: -1
    fillColor: Colours.generalBackgroundOpaque

    PathLine {
        relativeX: -root.wrapper.width - root.rounding
        relativeY: 0
    }
    PathArc {
        relativeX: root.rounding
        relativeY: root.rounding
        radiusX: root.rounding
        radiusY: root.rounding
    }
    PathLine {
        relativeX: 0
        relativeY: root.wrapper.height - root.rounding * 2
    }
    PathArc {
        relativeX: -root.utilsRoundingX
        relativeY: root.rounding
        radiusX: root.utilsRoundingX
        radiusY: root.rounding
    }
    PathLine {
        relativeX: root.wrapper.width + root.utilsRoundingX
        relativeY: 0
    }

    Behavior on fillColor {
        CAnim {}
    }
}
