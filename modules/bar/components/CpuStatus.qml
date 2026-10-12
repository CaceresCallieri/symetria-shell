pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.misc
import qs.services
import qs.config
import QtQuick

MouseArea {
    id: root

    property color colour: Colours.palette.m3tertiary

    // Computed values for display and tooltip (avoids duplicate calculations)
    readonly property int cpuUsagePercent: Math.round(SystemUsage.cpuPerc * 100)
    readonly property int cpuTemperature: Math.round(SystemUsage.cpuTemp)
    readonly property bool hasTemperature: SystemUsage.cpuTemp > 0

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    hoverEnabled: true

    // Subscribe to SystemUsage service when active
    Ref {
        service: SystemUsage
    }

    Row {
        id: content

        spacing: Appearance.spacing.small

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter

            text: "developer_board"
            color: Qt.alpha(root.colour, Appearance.emphasis.secondary)
        }

        BarReadout {
            anchors.verticalCenter: parent.verticalCenter

            value: root.cpuUsagePercent.toString()
            unit: "%"
            colour: root.colour
        }

        // Usage and temperature are two figures, so a quiet dot separates them.
        BarReadout {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasTemperature

            prefix: "· "
            value: root.cpuTemperature.toString()
            unit: "°"
            colour: root.colour
        }
    }

    Tooltip {
        target: root
        text: `CPU Usage: ${root.cpuUsagePercent}%\nTemperature: ${root.hasTemperature ? `${root.cpuTemperature}°C` : "N/A"}`
    }
}
