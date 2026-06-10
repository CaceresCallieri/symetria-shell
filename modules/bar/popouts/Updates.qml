pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import QtQuick

// The updates popout has two faces in ONE container:
//   * idle   → the Pacman / AUR / Total counts (hover to glance at what's pending)
//   * active → live progress of an in-flight run (started by clicking the bar
//              indicator). The run is independent of hover, so leaving and
//              re-entering the popout just shows whatever phase it's now in.
Column {
    id: root

    readonly property bool showProgress: UpdateRunner.running || UpdateRunner.finished
    readonly property bool awaitingPassword: UpdateRunner.phase === "password"

    spacing: Appearance.spacing.normal
    width: {
        if (root.awaitingPassword)
            return Config.bar.sizes.updatesPasswordWidth;
        return root.showProgress ? Config.bar.sizes.updatesProgressWidth : Config.bar.sizes.updatesWidth;
    }

    // --- IDLE: counts --------------------------------------------------------
    PillCardSection {
        width: parent.width
        contentMargins: Appearance.padding.normal
        visible: !root.showProgress

        Column {
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

            StyledText {
                width: parent.width
                visible: Updates.totalUpdates > 0
                text: qsTr("Click to update")
                font.pointSize: Appearance.font.size.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }

    PillCardSection {
        width: parent.width
        contentMargins: Appearance.padding.normal
        visible: !root.showProgress

        UpdateRow {
            icon: "󰒠"
            label: qsTr("Total")
            count: Updates.pacmanUpdates + Updates.aurUpdates
            emphasized: true
        }
    }

    // --- ACTIVE: live progress ----------------------------------------------
    PillCardSection {
        id: progressCard

        width: parent.width
        contentMargins: Appearance.padding.normal
        visible: root.showProgress

        readonly property bool isError: UpdateRunner.phase === "error"
        readonly property bool isDone: UpdateRunner.phase === "done"
        readonly property bool busy: UpdateRunner.running
        readonly property bool awaitingPassword: UpdateRunner.phase === "password"

        readonly property string phaseLabel: {
            switch (UpdateRunner.phase) {
            case "authenticating": return qsTr("Waiting for password…");
            case "syncing": return qsTr("Synchronising databases…");
            case "building": return qsTr("Building AUR packages…");
            case "installing": return qsTr("Installing packages…");
            case "done": return qsTr("Everything is up to date");
            case "error": return qsTr("Update failed");
            default: return qsTr("Preparing…");
            }
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Appearance.spacing.small

            // Password entry — shown while the run is blocked waiting for the sudo
            // password we feed to the script's stdin. Replaces the working widgets.
            // Compact: one label, then field + Update button on a single row.
            Column {
                width: parent.width
                spacing: Appearance.spacing.small
                visible: progressCard.awaitingPassword

                StyledText {
                    text: qsTr("Enter your password")
                    font.weight: 500
                }

                Row {
                    width: parent.width
                    spacing: Appearance.spacing.small

                    PasswordField {
                        id: passwordField

                        width: parent.width - updateButton.implicitWidth - parent.spacing
                        // Override PasswordField's roomy 48px default to match the
                        // button height for a compact single-row layout.
                        implicitHeight: updateButton.implicitHeight
                        isActive: progressCard.awaitingPassword
                        onSubmitted: if (password.length > 0) UpdateRunner.submitPassword(password)
                    }

                    RaisedTextButton {
                        id: updateButton

                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Update")
                        disabled: passwordField.password.length === 0
                        onClicked: UpdateRunner.submitPassword(passwordField.password)
                    }
                }
            }

            // Header: spinner / status glyph + phase label.
            Row {
                width: parent.width
                spacing: Appearance.spacing.small
                visible: !progressCard.awaitingPassword

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: Appearance.font.size.larger
                    implicitHeight: Appearance.font.size.larger

                    CircularIndicator {
                        anchors.fill: parent
                        implicitSize: parent.implicitHeight
                        strokeWidth: Appearance.padding.small * 0.5
                        running: progressCard.busy
                        visible: progressCard.busy
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: progressCard.isDone || progressCard.isError
                        text: progressCard.isError ? "error" : "check_circle"
                        fill: 1
                        color: progressCard.isError ? Colours.palette.m3error : Colours.palette.m3primary
                    }
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: progressCard.phaseLabel
                    font.weight: 500
                    color: progressCard.isError ? Colours.palette.m3error : Colours.palette.m3onSurface
                }
            }

            // Big live remaining count (hidden on error / done / password entry).
            Row {
                width: parent.width
                spacing: Appearance.spacing.small
                visible: !progressCard.isError && !progressCard.isDone && !progressCard.awaitingPassword

                StyledText {
                    id: remainingNumber
                    text: UpdateRunner.remaining.toString()
                    font.pointSize: Appearance.font.size.extraLarge
                    font.weight: 700
                    color: Colours.palette.m3primary

                    animate: true
                    animateProp: "scale"
                    animateFrom: 0.6
                    animateTo: 1
                }

                StyledText {
                    anchors.baseline: remainingNumber.baseline
                    text: UpdateRunner.remaining === 1 ? qsTr("update remaining") : qsTr("updates remaining")
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            // Determinate bar during install.
            Rectangle {
                width: parent.width
                visible: UpdateRunner.totalPackages > 0 && !progressCard.isDone && !progressCard.isError
                implicitHeight: Appearance.padding.small
                radius: height / 2
                color: Colours.palette.m3surfaceContainerHigh

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    radius: parent.radius
                    color: Colours.palette.m3primary
                    width: parent.width * (UpdateRunner.totalPackages > 0
                        ? UpdateRunner.installedCount / UpdateRunner.totalPackages
                        : 0)

                    Behavior on width {
                        Anim {}
                    }
                }
            }

            // Current package.
            StyledText {
                width: parent.width
                visible: UpdateRunner.currentPackage.length > 0 && !progressCard.isDone
                text: UpdateRunner.currentPackage
                font.family: Appearance.font.family.mono
                font.pointSize: Appearance.font.size.small
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
            }

            // Error message.
            StyledText {
                width: parent.width
                visible: progressCard.isError
                text: UpdateRunner.errorMessage
                font.pointSize: Appearance.font.size.small
                color: Colours.palette.m3error
                wrapMode: Text.WordWrap
            }

            // Live log tail — tall enough to read what's actually happening.
            StyledRect {
                width: parent.width
                visible: UpdateRunner.logTail.length > 0 && !progressCard.isDone
                implicitHeight: Appearance.font.size.small * 26
                radius: Appearance.rounding.small
                color: Colours.palette.m3surfaceContainerLow
                clip: true

                StyledText {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Appearance.padding.smaller

                    text: UpdateRunner.logTail
                    font.family: Appearance.font.family.mono
                    font.pointSize: Appearance.font.size.small
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
            }

            // Footer action.
            Item {
                width: parent.width
                implicitHeight: actionButton.implicitHeight

                RaisedTextButton {
                    id: actionButton
                    anchors.right: parent.right

                    text: progressCard.busy ? qsTr("Cancel") : qsTr("Dismiss")
                    onClicked: {
                        if (UpdateRunner.running)
                            UpdateRunner.cancel();
                        else
                            UpdateRunner.acknowledge();
                    }
                }
            }
        }
    }

    // Reusable row for an update source (idle view).
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
