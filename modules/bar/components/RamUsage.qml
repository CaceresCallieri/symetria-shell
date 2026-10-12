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
    // intentional var: JS object { value: real, unit: string } from SystemUsage.formatKib()
    readonly property var memUsedFormatted: SystemUsage.formatKib(SystemUsage.memUsed)
    // intentional var: JS object { value: real, unit: string } from SystemUsage.formatKib()
    readonly property var memTotalFormatted: SystemUsage.formatKib(SystemUsage.memTotal)
    readonly property int memUsagePercent: Math.round(SystemUsage.memPerc * 100)
    readonly property string gamingReadiness: SystemUsage.gamingReadiness

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
            color: Qt.alpha(root.colour, Appearance.emphasis.secondary)
        }

        // "17.5G": every unit formatKib returns (KiB, MiB, GiB, TiB) reads by
        // its first letter; the tooltip spells it out.
        BarReadout {
            anchors.verticalCenter: parent.verticalCenter

            value: root.memUsedFormatted.value.toFixed(1)
            unit: root.memUsedFormatted.unit.charAt(0)
            colour: root.colour
        }
    }

    Tooltip {
        target: root
        text: `RAM Used: ${root.memUsedFormatted.value.toFixed(1)} ${root.memUsedFormatted.unit}\nTotal: ${root.memTotalFormatted.value.toFixed(1)} ${root.memTotalFormatted.unit}\nUsage: ${root.memUsagePercent}%\nGaming Readiness: ${root.gamingReadiness}`
    }
}
