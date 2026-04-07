pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
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
        function onCurrentNameChanged() {
            if (root.wrapper.currentName === "wirelesspassword") {
                // Update network when popout becomes active
                Qt.callLater(() => {
                    // Try to get network from parent Content's networkPopout
                    const content = root.parent?.parent?.parent;
                    if (content) {
                        const networkPopout = content.children.find(c => c.name === "network");
                        if (networkPopout && networkPopout.item) {
                            root.network = networkPopout.item.passwordNetwork;
                        }
                    }
                    // Force focus to password container when popout becomes active
                    // Use Timer for actual delay to ensure dialog is fully rendered
                    focusTimer.start();
                });
            }
        }
    }

    Timer {
        id: focusTimer
        interval: 150
        onTriggered: {
            root.forceActiveFocus();
            passwordField.forceActiveFocus();
        }
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
            connectButton.hasError = false;
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

            Timer {
                interval: 50
                running: root.shouldBeVisible && (!root.network || !root.network.ssid)
                repeat: true
                property int attempts: 0
                onTriggered: {
                    attempts++;
                    // Keep trying to get network from Network component
                    const content = root.parent?.parent?.parent;
                    if (content) {
                        const networkPopout = content.children.find(c => c.name === "network");
                        if (networkPopout && networkPopout.item && networkPopout.item.passwordNetwork) {
                            root.network = networkPopout.item.passwordNetwork;
                        }
                    }
                    // Stop if we got it or after 20 attempts (1 second)
                    if ((root.network && root.network.ssid) || attempts >= 20) {
                        stop();
                        attempts = 0;
                    }
                }
                onRunningChanged: {
                    if (!running) {
                        attempts = 0;
                    }
                }
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
                    inactiveColour: Colours.palette.m3secondaryContainer
                    inactiveOnColour: Colours.palette.m3onSecondaryContainer
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

                        // Clear any previous error
                        hasError = false;

                        // Set connecting state
                        connecting = true;
                        enabled = false;
                        text = qsTr("Connecting...");

                        // Connect to network
                        NetworkConnection.connectWithPassword(root.network, password, result => {
                            if (result && result.success)
                            // Connection successful, monitor will handle the rest
                            {} else if (result && result.needsPassword) {
                                // Shouldn't happen since we provided password
                                connectionMonitor.stop();
                                connecting = false;
                                hasError = true;
                                enabled = true;
                                text = qsTr("Connect");
                                passwordField.password = "";
                                // Delete the failed connection
                                if (root.network && root.network.ssid) {
                                    NmcliWifi.forgetNetwork(root.network.ssid);
                                }
                            } else {
                                // Connection failed immediately - show error
                                connectionMonitor.stop();
                                connecting = false;
                                hasError = true;
                                enabled = true;
                                text = qsTr("Connect");
                                passwordField.password = "";
                                // Delete the failed connection
                                if (root.network && root.network.ssid) {
                                    NmcliWifi.forgetNetwork(root.network.ssid);
                                }
                            }
                        });

                        // Start monitoring connection
                        connectionMonitor.start();
                    }
                }
            }
        }
    }

    function checkConnectionStatus(): void {
        if (!root.shouldBeVisible || !connectButton.connecting) {
            return;
        }

        // Check if we're connected to the target network (case-insensitive SSID comparison)
        const isConnected = root.network && NmcliWifi.active && NmcliWifi.active.ssid && NmcliWifi.active.ssid.toLowerCase().trim() === root.network.ssid.toLowerCase().trim();

        if (isConnected) {
            // Successfully connected - give it a moment for network list to update
            // Use Timer for actual delay
            connectionSuccessTimer.start();
            return;
        }

        // Check for connection failures - if pending connection was cleared but we're not connected
        if (NmcliWifi.pendingConnection === null && connectButton.connecting) {
            // Wait a bit more before giving up (allow time for connection to establish)
            if (connectionMonitor.repeatCount > 10) {
                connectionMonitor.stop();
                connectButton.connecting = false;
                connectButton.hasError = true;
                connectButton.enabled = true;
                connectButton.text = qsTr("Connect");
                passwordField.password = "";
                // Delete the failed connection
                if (root.network && root.network.ssid) {
                    NmcliWifi.forgetNetwork(root.network.ssid);
                }
            }
        }
    }

    Timer {
        id: connectionMonitor
        interval: 1000
        repeat: true
        triggeredOnStart: false
        property int repeatCount: 0

        onTriggered: {
            repeatCount++;
            root.checkConnectionStatus();
        }

        onRunningChanged: {
            if (!running) {
                repeatCount = 0;
            }
        }
    }

    Timer {
        id: connectionSuccessTimer
        interval: 500
        onTriggered: {
            // Double-check connection is still active
            if (root.shouldBeVisible && NmcliWifi.active && NmcliWifi.active.ssid) {
                const stillConnected = NmcliWifi.active.ssid.toLowerCase().trim() === root.network.ssid.toLowerCase().trim();
                if (stillConnected) {
                    connectionMonitor.stop();
                    connectButton.connecting = false;
                    connectButton.text = qsTr("Connect");
                    // Return to network popout on successful connection
                    if (root.wrapper.currentName === "wirelesspassword") {
                        root.wrapper.currentName = "network";
                    }
                    closeDialog();
                }
            }
        }
    }

    Connections {
        target: NmcliWifi
        function onActiveChanged() {
            if (root.shouldBeVisible) {
                root.checkConnectionStatus();
            }
        }
        function onConnectionFailed(ssid: string) {
            if (root.shouldBeVisible && root.network && root.network.ssid === ssid && connectButton.connecting) {
                connectionMonitor.stop();
                connectButton.connecting = false;
                connectButton.hasError = true;
                connectButton.enabled = true;
                connectButton.text = qsTr("Connect");
                passwordField.password = "";
                // Delete the failed connection
                NmcliWifi.forgetNetwork(ssid);
            }
        }
    }

    function closeDialog(): void {
        if (isClosing) {
            return;
        }

        isClosing = true;
        passwordField.password = "";
        connectButton.connecting = false;
        connectButton.hasError = false;
        connectButton.text = qsTr("Connect");
        connectionMonitor.stop();

        // Return to network popout
        if (root.wrapper.currentName === "wirelesspassword") {
            root.wrapper.currentName = "network";
        }
    }
}

