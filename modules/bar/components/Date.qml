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

        active: Config.bar.date.showIcon
        visible: active
        asynchronous: true

        sourceComponent: MaterialIcon {
            text: "calendar_month"
            color: Qt.alpha(root.colour, Appearance.emphasis.secondary)
        }
    }

    // "Sun 11 Oct": the day of the month is the figure, the weekday and the
    // month recede around it.
    BarReadout {
        anchors.verticalCenter: parent.verticalCenter

        prefix: `${Time.format("ddd")} `
        value: Time.format("d")
        unit: ` ${Time.format("MMM")}`
        colour: root.colour
    }
}
