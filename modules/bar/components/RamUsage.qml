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
    readonly property var memUsedFormatted: SystemUsage.formatKib(SystemUsage.memUsed)
    readonly property var memTotalFormatted: SystemUsage.formatKib(SystemUsage.memTotal)
    readonly property int memUsagePercent: Math.round(SystemUsage.memPerc * 100)

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

            text: "memory_alt"
            color: root.colour
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter

            text: `${root.memUsedFormatted.value.toFixed(1)} ${root.memUsedFormatted.unit}`
            font.pointSize: Appearance.font.size.smaller
            font.family: Appearance.font.family.mono
            color: root.colour
        }
    }

    Tooltip {
        target: root
        text: `RAM Used: ${root.memUsedFormatted.value.toFixed(1)} ${root.memUsedFormatted.unit}\nTotal: ${root.memTotalFormatted.value.toFixed(1)} ${root.memTotalFormatted.unit}\nUsage: ${root.memUsagePercent}%`
    }
}
