pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick

Column {
    id: root

    spacing: Appearance.spacing.normal
    width: Config.bar.sizes.updatesWidth

    // Section 1 — Sources card: Pacman + AUR counts.
    PillCardSection {
        width: parent.width
        contentMargins: Appearance.padding.normal

        Column {
            id: sourcesColumn

            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Appearance.spacing.small

            StyledText {
                text: Updates.hasData
                    ? qsTr("Available Updates: %1").arg(Updates.pacmanUpdates + Updates.aurUpdates)
                    : qsTr("Checking for updates...")
                font.weight: 500
            }

            UpdateRow {
                icon: "󰮯"
                label: qsTr("Pacman")
                count: Updates.pacmanUpdates
            }

            UpdateRow {
                icon: "󰣇"
                label: qsTr("AUR")
                count: Updates.aurUpdates
            }
        }
    }

    // Section 2 — Total: own card so it reads as a visual peer to the sources card.
    PillCardSection {
        width: parent.width
        contentMargins: Appearance.padding.normal

        UpdateRow {
            id: totalRow

            anchors.left: parent.left

            icon: "󰒠"
            label: qsTr("Total")
            count: Updates.pacmanUpdates + Updates.aurUpdates
            emphasized: true
        }
    }

    // Reusable row component for update sources
    component UpdateRow: Row {
        required property string icon
        required property string label
        required property int count
        property bool emphasized: false

        spacing: Appearance.spacing.normal

        StyledText {
            text: parent.icon
            font.family: Appearance.font.family.mono
            color: Colours.palette.m3primary
        }

        StyledText {
            text: qsTr("%1: %2").arg(parent.label).arg(parent.count)
            font.weight: parent.emphasized ? 500 : 400
        }
    }
}
