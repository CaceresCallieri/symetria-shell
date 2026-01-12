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
            color: root.colour
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter

            text: `${root.cpuUsagePercent}%${root.hasTemperature ? `|${root.cpuTemperature}°` : ""}`
            font.pointSize: Appearance.font.size.smaller
            font.family: Appearance.font.family.mono
            color: root.colour
        }
    }

    Tooltip {
        target: root
        text: `CPU Usage: ${root.cpuUsagePercent}%\nTemperature: ${root.hasTemperature ? `${root.cpuTemperature}°C` : "N/A"}`
    }
}
