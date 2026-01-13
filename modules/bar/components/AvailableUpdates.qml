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

    // Tooltip text with breakdown by source
    readonly property string tooltipText: {
        if (!Updates.hasData) return "Loading...";

        const pacmanLine = `󰮯 Pacman: ${Updates.pacmanUpdates}`;
        const aurLine = `󰣇 AUR: ${Updates.aurUpdates}`;
        const flatpakLine = Updates.flatpakInstalled
            ? ` Flatpak: ${Updates.flatpakUpdates}`
            : " Flatpak: not installed";
        const totalLine = `󰒠 Total: ${Updates.totalUpdates}`;

        return `${pacmanLine}\n${aurLine}\n${flatpakLine}\n${totalLine}`;
    }

    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    hoverEnabled: true

    // Subscribe to Updates service when active
    Ref {
        service: Updates
    }

    Row {
        id: content

        spacing: Appearance.spacing.small

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter

            text: Updates.totalUpdates === 0 ? "verified" : "download"
            color: root.colour
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: Updates.totalUpdates > 0

            text: Updates.totalUpdates.toString()
            font.pointSize: Appearance.font.size.smaller
            font.family: Appearance.font.family.mono
            color: root.colour
        }
    }

    Tooltip {
        target: root
        text: root.tooltipText
    }
}
