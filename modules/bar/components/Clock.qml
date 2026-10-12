pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick

Row {
    id: root

    property color colour: Colours.palette.m3tertiary

    spacing: Appearance.spacing.small

    Loader {
        anchors.verticalCenter: parent.verticalCenter

        active: Config.bar.clock.showIcon
        visible: active
        asynchronous: true

        sourceComponent: MaterialIcon {
            text: "schedule"
            color: Qt.alpha(root.colour, Appearance.emphasis.secondary)
        }
    }

    BarReadout {
        anchors.verticalCenter: parent.verticalCenter

        value: Time.format(Config.services.useTwelveHourClock ? "hh:mm A" : "hh:mm")
        colour: root.colour
    }
}
