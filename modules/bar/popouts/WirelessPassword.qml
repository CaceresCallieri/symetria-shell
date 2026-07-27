pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import qs.utils
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property Item wrapper
    // intentional var: nullable JS object from network scan data ({ ssid, bssid, security, ... })
    property var network: null
    property bool isClosing: false

    readonly property bool shouldBeVisible: root.wrapper.currentName === "wirelesspassword"

    Connections {
        target: root.wrapper
        function onCurrentNameChanged(): void {
            if (root.wrapper.currentName === "wirelesspassword") {
                // Force focus to password container when popout becomes active.
                // Network is set by Content.qml's reactive binding.
                focusTimer.start();
            }
        }
    }

    Timer {
        id: focusTimer
        // PasswordField manages its own focus via isActive → _focusTimer (50ms).
        // WirelessPassword only needs to ensure the outer ColumnLayout has focus
        // so keyboard events route into the component tree.
        interval: 150
        onTriggered: root.forceActiveFocus()
    }

    spacing: Appearance.spacing.normal

    implicitWidth: 400
    implicitHeight: content.implicitHeight + Appearance.padding.large * 2

    visible: shouldBeVisible || isClosing
    enabled: shouldBeVisible && !isClosing
    focus: enabled

    Component.onCompleted: {
        if (shouldBeVisible) {
            // Use Timer for actual delay to ensure dialog is fully rendered
            focusTimer.start();
        }
    }

    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            // Reset any stale state from a previous attempt that may have ended
            // without going through closeDialog (e.g. popout navigated away
            // externally while connecting). Without this the next open can
            // appear stuck in "Connecting…" with a disabled Connect button.
            connectButton.hasError = false;
            connectButton.connecting = false;
            // Restore the declarative binding severed by the imperative `enabled = false`
            // at connection start. Without this, the Connect button stays permanently
            // disabled even after `connecting` is reset above.
            connectButton.enabled = Qt.binding(() => passwordField.password.length > 0 && !connectButton.connecting);
            connectButton.text = qsTr("Connect");
            focusTimer.start();
        }
    }

    Keys.onEscapePressed: closeDialog()

    StyledRect {
        Layout.fillWidth: true
        Layout.preferredWidth: 400
        implicitHeight: content.implicitHeight + Appearance.padding.large * 2

        radius: Appearance.rounding.normal
        color: Colours.tPalette.m3surfaceContainer
        visible: root.shouldBeVisible || root.isClosing
        opacity: root.shouldBeVisible && !root.isClosing ? 1 : 0
        scale: root.shouldBeVisible && !root.isClosing ? 1 : 0.7

        Behavior on opacity {
            Anim {}
        }

        Behavior on scale {
            Anim {}
        }

        ParallelAnimation {
            running: root.isClosing
            onFinished: {
                if (root.isClosing) {
                    root.isClosing = false;
                }
            }

            Anim {
                target: parent
                property: "opacity"
                to: 0
            }
            Anim {
                target: parent
                property: "scale"
                to: 0.7
            }
        }

        Keys.onEscapePressed: root.closeDialog()

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Appearance.padding.large

            spacing: Appearance.spacing.normal

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: "lock"
                font.pointSize: Appearance.font.size.extraLarge * 2
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Enter password")
                font.pointSize: Appearance.font.size.large
                font.weight: 500
            }

            StyledText {
                id: networkNameText
                Layout.alignment: Qt.AlignHCenter
                text: {
                    if (root.network) {
                        const ssid = root.network.ssid;
                        if (ssid && ssid.length > 0) {
                            return qsTr("Network: %1").arg(ssid);
                        }
                    }
                    return qsTr("Network: Unknown");
                }
                color: Colours.palette.m3outline
                font.pointSize: Appearance.font.size.small
            }

            StyledText {
                id: statusText

                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Appearance.spacing.small
                visible: connectButton.connecting || connectButton.hasError
                text: {
                    if (connectButton.hasError) {
                        return qsTr("Connection failed. Please check your password and try again.");
                    }
                    if (connectButton.connecting) {
                        return qsTr("Connecting...");
                    }
                    return "";
                }
                color: connectButton.hasError ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.small
                font.weight: 400
                wrapMode: Text.WordWrap
                Layout.maximumWidth: parent.width - Appearance.padding.large * 2
            }

            PasswordField {
                id: passwordField

                Layout.topMargin: Appearance.spacing.large
                Layout.fillWidth: true
                isActive: root.shouldBeVisible
                hasError: connectButton.hasError
                onSubmitted: { if (connectButton.enabled) connectButton.clicked(); }
                onErrorCleared: connectButton.hasError = false
            }

            RowLayout {
                Layout.topMargin: Appearance.spacing.normal
                Layout.fillWidth: true
                spacing: Appearance.spacing.normal

                TextButton {
                    id: cancelButton

                    Layout.fillWidth: true
                    Layout.minimumHeight: Appearance.font.size.normal + Appearance.padding.normal * 2
                    inactiveColour: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle).background
                    inactiveOnColour: Colours.palette.m3onSurface
                    text: qsTr("Cancel")

                    onClicked: root.closeDialog()
                }

                TextButton {
                    id: connectButton

                    property bool connecting: false
                    property bool hasError: false

                    Layout.fillWidth: true
                    Layout.minimumHeight: Appearance.font.size.normal + Appearance.padding.normal * 2
                    inactiveColour: Colours.palette.m3primary
                    inactiveOnColour: Colours.palette.m3onPrimary
                    text: qsTr("Connect")
                    enabled: passwordField.password.length > 0 && !connecting

                    onClicked: {
                        if (!root.network || connecting) {
                            return;
                        }

                        const password = passwordField.password;
                        if (!password || password.length === 0) {
                            return;
                        }

                        hasError = false;
                        connecting = true;
                        enabled = false;
                        text = qsTr("Connecting...");

                        // The callback is authoritative and always fires exactly
                        // once — NmcliWifi derives it from nmcli's exit code, not
                        // from polling. Every terminal state is handled right here.
                        NetworkConnection.connectWithPassword(root.network, password, result => {
                            if (result && result.success) {
                                root.closeDialog();
                                return;
                            }

                            connecting = false;
                            hasError = true;
                            enabled = true;
                            text = qsTr("Connect");
                            passwordField.password = "";

                            // REGRESSION GUARD: do NOT call forgetNetwork() here.
                            // This ran on every failure, including failures that
                            // were not failures — a connection NetworkManager had
                            // already activated got its profile deleted, tearing
                            // down working wifi (verified 2026-07-27). Stale
                            // profiles are cleared by connectWithSecret at the
                            // start of the next attempt, where nothing is in flight.
                        });
                    }
                }
            }
        }
    }

    // NOTE: this dialog deliberately has NO polling monitor.
    //
    // REGRESSION GUARD: it used to run a 1s repeating timer that compared
    // NmcliWifi.active.ssid against the target and, past 15 ticks, declared
    // failure and deleted the profile. Every part of that was unsound: `active`
    // is the first active AP across ALL radios (not necessarily this one), and a
    // connection slower than the threshold was reported as a failure and then
    // destroyed. The connect callback now reports the real outcome exactly once.

    function closeDialog(): void {
        if (isClosing) {
            return;
        }

        isClosing = true;
        passwordField.password = "";
        connectButton.connecting = false;
        connectButton.hasError = false;
        connectButton.text = qsTr("Connect");

        // Return to network popout
        if (root.wrapper.currentName === "wirelesspassword") {
            root.wrapper.currentName = "network";
        }
    }
}

