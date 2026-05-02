pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick

Column {
    id: root

    spacing: Appearance.spacing.normal
    width: Config.bar.sizes.updatesWidth

    // Section 1 — Sources card: header text + per-source counts
    // (Pacman, AUR). Replaces the prior bare-text-on-popout flow.
    Item {
        width: parent.width
        implicitHeight: sourcesColumn.implicitHeight + Appearance.padding.normal * 2

        PillCard {
            anchors.fill: parent
        }

        Column {
            id: sourcesColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Appearance.padding.normal
            anchors.rightMargin: Appearance.padding.normal
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

    // Section 2 — Total card: emphasized aggregate count, framed on its
    // own to mirror the prior divider's visual hierarchy.
    Item {
        width: parent.width
        implicitHeight: totalRow.implicitHeight + Appearance.padding.normal * 2

        PillCard {
            anchors.fill: parent
        }

        UpdateRow {
            id: totalRow

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Appearance.padding.normal

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
