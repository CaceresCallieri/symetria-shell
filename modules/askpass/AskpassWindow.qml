pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

Scope {
    id: root

    property bool visible: false
    property string promptMessage: ""
    property string fifoPath: ""
    property string passwordBuffer: ""  // Moved to root for synchronous clearing in show()

    function show(message: string, fifoPath: string): void {
        // Clear sensitive data FIRST, before dialog becomes visible
        // This prevents race condition where user could type before clear
        root.passwordBuffer = "";

        root.promptMessage = message || "Password:";
        root.fifoPath = fifoPath;
        root.visible = true;

        console.log("Askpass: Dialog shown for FIFO:", fifoPath);
    }

    function hide(): void {
        root.visible = false;
        root.promptMessage = "";
        root.fifoPath = "";
    }

    // POSIX shell escaping: wrap in single quotes, escape embedded quotes
    // This prevents command injection when passing user data to shell commands
    function shellEscape(str: string): string {
        return "'" + str.replace(/'/g, "'\\''") + "'";
    }

    function submitPassword(password: string): void {
        if (!root.fifoPath) {
            root.hide();
            return;
        }

        writeProcess.fifoPath = root.fifoPath;
        writeProcess.password = password;
        writeProcess.running = true;
    }

    function cancel(): void {
        // Write empty string to unblock the reading process
        if (root.fifoPath) {
            cancelProcess.fifoPath = root.fifoPath;
            cancelProcess.running = true;
        } else {
            root.hide();
        }
    }

    Process {
        id: writeProcess

        property string fifoPath: ""
        property string password: ""

        // Use printf with shell-escaped password to safely write to FIFO
        // printf '%s' avoids adding a trailing newline which would break password
        command: ["sh", "-c", `printf '%s' ${root.shellEscape(password)} > ${root.shellEscape(fifoPath)}`]

        onRunningChanged: {
            if (running) writeTimeout.start();
            else writeTimeout.stop();
        }

        onExited: (exitCode, exitStatus) => {
            writeTimeout.stop();
            if (exitCode !== 0) {
                console.error("Askpass: Write failed with exitCode:", exitCode);
            } else {
                console.log("Askpass: Password submitted successfully");
            }
            root.hide();
        }
    }

    Timer {
        id: writeTimeout
        interval: 5000  // 5 second timeout
        onTriggered: {
            console.error("Askpass: Write timeout - forcing close");
            writeProcess.kill();
            root.hide();
        }
    }

    Process {
        id: cancelProcess

        property string fifoPath: ""

        // Write sentinel value to signal cancellation
        command: ["sh", "-c", `printf '%s' '__CANCELLED__' > ${root.shellEscape(fifoPath)}`]

        onRunningChanged: {
            if (running) cancelTimeout.start();
            else cancelTimeout.stop();
        }

        onExited: (exitCode, exitStatus) => {
            cancelTimeout.stop();
            if (exitCode !== 0) {
                console.error("Askpass: Cancel write failed with exitCode:", exitCode);
            } else {
                console.log("Askpass: Cancellation sent");
            }
            root.hide();
        }
    }

    Timer {
        id: cancelTimeout
        interval: 5000  // 5 second timeout
        onTriggered: {
            console.error("Askpass: Cancel timeout - forcing close");
            cancelProcess.kill();
            root.hide();
        }
    }

    Variants {
        model: root.visible ? Quickshell.screens : []

        StyledWindow {
            id: win

            required property ShellScreen modelData

            screen: modelData
            name: "askpass"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            // Scrim background
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.6)

                Behavior on opacity {
                    Anim {}
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.cancel()
                }
            }

            // Dialog
            StyledRect {
                id: dialog

                anchors.centerIn: parent

                implicitWidth: 400
                implicitHeight: content.implicitHeight + Appearance.padding.large * 2

                radius: Appearance.rounding.normal
                color: Colours.tPalette.m3surface

                // Capture key events
                focus: true
                Keys.onEscapePressed: root.cancel()
                Keys.onPressed: event => {
                    if (!dialog.activeFocus) {
                        dialog.forceActiveFocus();
                    }

                    if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                        if (root.passwordBuffer.length > 0) {
                            root.submitPassword(root.passwordBuffer);
                        }
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Backspace) {
                        if (event.modifiers & Qt.ControlModifier) {
                            root.passwordBuffer = "";
                        } else {
                            root.passwordBuffer = root.passwordBuffer.slice(0, -1);
                        }
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.cancel();
                        event.accepted = true;
                    } else if (event.text && event.text.length > 0) {
                        // Filter out control characters (0x00-0x1F and 0x7F)
                        // This prevents Tab, Ctrl sequences, etc. from entering password
                        const isControlChar = event.key === Qt.Key_Tab ||
                            /[\x00-\x1F\x7F]/.test(event.text);
                        if (!isControlChar) {
                            root.passwordBuffer += event.text;
                        }
                        event.accepted = true;
                    }
                }

                Component.onCompleted: {
                    Qt.callLater(() => dialog.forceActiveFocus());
                }

                Connections {
                    target: root

                    function onVisibleChanged(): void {
                        if (root.visible) {
                            // Password buffer is cleared in show() before visibility changes
                            Qt.callLater(() => dialog.forceActiveFocus());
                        }
                    }
                }

                ColumnLayout {
                    id: content

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Appearance.padding.large

                    spacing: Appearance.spacing.normal

                    // Lock icon
                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "lock"
                        font.pointSize: Appearance.font.size.extraLarge * 2
                    }

                    // Title
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Authentication Required")
                        font.pointSize: Appearance.font.size.large
                        font.weight: 500
                    }

                    // Prompt message from sudo
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.promptMessage.replace(/:$/, "")
                        color: Colours.palette.m3outline
                        font.pointSize: Appearance.font.size.small
                    }

                    // Password input container
                    Item {
                        id: passwordContainer

                        Layout.topMargin: Appearance.spacing.large
                        Layout.fillWidth: true
                        implicitHeight: Math.max(48, charList.implicitHeight + Appearance.padding.normal * 2)

                        StyledRect {
                            anchors.fill: parent
                            radius: Appearance.rounding.normal
                            color: dialog.activeFocus ? Qt.lighter(Colours.tPalette.m3surfaceContainer, 1.05) : Colours.tPalette.m3surfaceContainer
                            border.width: dialog.activeFocus ? 4 : 1
                            border.color: dialog.activeFocus ? Colours.palette.m3primary : Colours.palette.m3outline

                            Behavior on border.color {
                                CAnim {}
                            }

                            Behavior on border.width {
                                CAnim {}
                            }

                            Behavior on color {
                                CAnim {}
                            }
                        }

                        StateLayer {
                            hoverEnabled: false
                            cursorShape: Qt.IBeamCursor

                            function onClicked(): void {
                                dialog.forceActiveFocus();
                            }
                        }

                        // Placeholder text
                        StyledText {
                            id: placeholder

                            anchors.centerIn: parent
                            text: qsTr("Password")
                            color: Colours.palette.m3outline
                            font.pointSize: Appearance.font.size.normal
                            font.family: Appearance.font.family.mono
                            opacity: root.passwordBuffer ? 0 : 1

                            Behavior on opacity {
                                Anim {}
                            }
                        }

                        // Password dots
                        ListView {
                            id: charList

                            readonly property int fullWidth: count * (implicitHeight + spacing) - spacing

                            anchors.centerIn: parent
                            implicitWidth: fullWidth
                            implicitHeight: Appearance.font.size.normal

                            orientation: Qt.Horizontal
                            spacing: Appearance.spacing.small / 2
                            interactive: false

                            model: ScriptModel {
                                values: root.passwordBuffer.split("")
                            }

                            delegate: StyledRect {
                                id: charDot

                                implicitWidth: implicitHeight
                                implicitHeight: charList.implicitHeight

                                color: Colours.palette.m3onSurface
                                radius: Appearance.rounding.small / 2

                                opacity: 0
                                scale: 0
                                Component.onCompleted: {
                                    opacity = 1;
                                    scale = 1;
                                }
                                ListView.onRemove: removeAnim.start()

                                SequentialAnimation {
                                    id: removeAnim

                                    PropertyAction {
                                        target: charDot
                                        property: "ListView.delayRemove"
                                        value: true
                                    }
                                    ParallelAnimation {
                                        Anim {
                                            target: charDot
                                            property: "opacity"
                                            to: 0
                                        }
                                        Anim {
                                            target: charDot
                                            property: "scale"
                                            to: 0.5
                                        }
                                    }
                                    PropertyAction {
                                        target: charDot
                                        property: "ListView.delayRemove"
                                        value: false
                                    }
                                }

                                Behavior on opacity {
                                    Anim {}
                                }

                                Behavior on scale {
                                    Anim {
                                        duration: Appearance.anim.durations.expressiveFastSpatial
                                        easing.bezierCurve: Appearance.anim.curves.expressiveFastSpatial
                                    }
                                }
                            }

                            Behavior on implicitWidth {
                                Anim {}
                            }
                        }
                    }

                    // Buttons
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

                            onClicked: root.cancel()
                        }

                        TextButton {
                            id: submitButton

                            Layout.fillWidth: true
                            Layout.minimumHeight: Appearance.font.size.normal + Appearance.padding.normal * 2
                            inactiveColour: Colours.palette.m3primary
                            inactiveOnColour: Colours.palette.m3onPrimary
                            text: qsTr("Authenticate")
                            enabled: root.passwordBuffer.length > 0

                            onClicked: root.submitPassword(root.passwordBuffer)
                        }
                    }
                }
            }
        }
    }
}
