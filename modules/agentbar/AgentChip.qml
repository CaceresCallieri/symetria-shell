pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick

/// Individual agent display: just the instance number.
StyledText {
    id: root

    required property int instanceNum
    required property bool active

    text: root.instanceNum
    color: root.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
    font.weight: root.active ? Font.DemiBold : Font.Normal
    font.pointSize: Appearance.font.size.small
}
