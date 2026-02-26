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

    spacing: Appearance.spacing.smaller

    // Colored dot
    Rectangle {
        implicitWidth: 8
        implicitHeight: 8
        radius: 4
        color: root.dotColor
        opacity: root.active ? 1.0 : 0.5

        Behavior on opacity {
            Anim {}
        }
    }

    // Instance number + title
    StyledText {
        text: `#${root.instanceNum} ${root.title}`
        color: root.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
        font.weight: root.active ? Font.DemiBold : Font.Normal
        font.pointSize: Appearance.font.size.smaller
        elide: Text.ElideRight
        Layout.maximumWidth: 200
    }
}
