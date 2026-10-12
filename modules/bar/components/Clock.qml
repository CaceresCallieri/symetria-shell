pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.utils
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

        sourceComponent: BarIcon {
            icon: "schedule"
            tint: root.colour
            tintAlpha: BarGlyphs.secondaryAlpha
        }
    }

    BarReadout {
        anchors.verticalCenter: parent.verticalCenter

        value: Time.format(Config.services.useTwelveHourClock ? "hh:mm A" : "hh:mm")
        colour: root.colour
    }
}
