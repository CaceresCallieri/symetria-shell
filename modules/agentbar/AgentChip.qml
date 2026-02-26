pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

/// Individual agent display: colored dot + "#N title"
RowLayout {
    id: root

    required property int instanceNum
    required property string title
    required property color dotColor
    required property bool active
    property bool isSttTarget: false

    spacing: Appearance.spacing.small

    // Colored dot
    Rectangle {
        implicitWidth: 6
        implicitHeight: 6
        radius: 3
        color: root.dotColor
        opacity: root.active ? 1.0 : 0.5
        scale: root.isSttTarget ? 1.5 : 1.0

        Behavior on opacity {
            Anim {}
        }

        Behavior on scale {
            Anim {
                duration: Appearance.anim.durations.normal
                easing.type: Easing.OutCubic
            }
        }
    }

    // Instance number + title
    StyledText {
        text: `#${root.instanceNum} ${root.title}`
        color: root.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
        font.weight: root.active ? Font.DemiBold : Font.Normal
        font.pointSize: Appearance.font.size.small
        elide: Text.ElideRight
        Layout.maximumWidth: 150
    }
}
