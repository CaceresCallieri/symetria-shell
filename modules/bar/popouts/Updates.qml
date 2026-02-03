pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick

Column {
    id: root

    spacing: Appearance.spacing.normal
    width: Config.bar.sizes.updatesWidth

    // Header
    StyledText {
        text: Updates.hasData
            ? qsTr("Available Updates: %1").arg(Updates.pacmanUpdates + Updates.aurUpdates)
            : qsTr("Checking for updates...")
        font.weight: 500
    }

    // Update rows
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

    // Separator
    Rectangle {
        width: parent.width
        height: 1
        color: Colours.palette.m3outline
    }

    // Total row (emphasized)
    UpdateRow {
        icon: "󰒠"
        label: qsTr("Total")
        count: Updates.pacmanUpdates + Updates.aurUpdates
        emphasized: true
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
