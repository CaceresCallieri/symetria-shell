import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Shapes

ShapePath {
    id: root

    required property Wrapper wrapper
    required property bool invertBottomRounding
    readonly property real rounding: wrapper.isDetached ? Appearance.rounding.normal : Config.border.rounding
    readonly property bool flatten: wrapper.height < rounding * 2
    readonly property real roundingY: flatten ? wrapper.height / 2 : rounding
    readonly property real bottomPadding: Appearance.padding.normal
    property real ibr: invertBottomRounding ? -1 : 1

    // For top-bar: attached when near top (y small), detached when away from top
    // Affects Y component of TOP corners (like sideRounding affected Y of LEFT corners)
    property real topRounding: wrapper.y < rounding ? 1 : -1

    strokeWidth: -1
    fillColor: Colours.palette.m3surface

    // Arc 1: Top-left corner
    // topRounding affects Y: goes DOWN when attached (1), UP when detached (-1)
    PathArc {
        relativeX: root.rounding
        relativeY: root.roundingY * root.topRounding
        radiusX: root.rounding
        radiusY: root.roundingY
        direction: root.topRounding < 0 ? PathArc.Counterclockwise : PathArc.Clockwise
    }

    // Line 1: Left edge (going down)
    PathLine {
        relativeX: 0
        relativeY: root.wrapper.height - root.roundingY * 2 + root.bottomPadding
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
        relativeY: -(root.wrapper.height - root.roundingY * 2 + root.bottomPadding)
    }

    // Arc 4: Top-right corner
    // topRounding affects Y: goes UP when attached (-1*1=-1), DOWN when detached (-1*-1=1)
    PathArc {
        relativeX: root.rounding
        relativeY: -root.roundingY * root.topRounding
        radiusX: root.rounding
        radiusY: root.roundingY
        direction: root.topRounding < 0 ? PathArc.Counterclockwise : PathArc.Clockwise
    }

    // Top edge auto-closes back to start

    Behavior on fillColor {
        CAnim {}
    }

    Behavior on ibr {
        Anim {}
    }

    Behavior on topRounding {
        Anim {}
    }
}
