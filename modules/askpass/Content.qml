pragma ComponentBehavior: Bound

import "services"
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities

    readonly property int padding: Appearance.padding.large
    readonly property int rounding: Appearance.rounding.large

    implicitWidth: dialog.implicitWidth
    implicitHeight: dialog.implicitHeight + padding

    // Handle visibility changes
    Connections {
        target: root.visibilities

        function onAskpassChanged(): void {
            if (root.visibilities.askpass) {
                Qt.callLater(() => dialog.forceActiveFocus());
            }
        }
    }

    // Dialog container
    StyledRect {
        id: dialog

        anchors.top: parent.top
        anchors.topMargin: root.padding
        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth: 400
        implicitHeight: content.implicitHeight + Appearance.padding.large * 2

        radius: Appearance.rounding.normal
        color: "transparent"

        // Capture key events
        focus: true
        Keys.onEscapePressed: AskpassStore.cancel()
        Keys.onPressed: event => {
            if (!dialog.activeFocus) {
                dialog.forceActiveFocus();
            }

            if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                if (AskpassStore.passwordBuffer.length > 0) {
                    AskpassStore.submitPassword(AskpassStore.passwordBuffer);
                }
                event.accepted = true;
            } else if (event.key === Qt.Key_Backspace) {
                if (event.modifiers & Qt.ControlModifier) {
                    AskpassStore.passwordBuffer = "";
                } else {
                    AskpassStore.passwordBuffer = AskpassStore.passwordBuffer.slice(0, -1);
                }
                event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                AskpassStore.cancel();
                event.accepted = true;
            } else if (event.text && event.text.length > 0) {
                // Filter out control characters (0x00-0x1F and 0x7F)
                // This prevents Tab, Ctrl sequences, etc. from entering password
                const isControlChar = event.key === Qt.Key_Tab ||
                    /[\x00-\x1F\x7F]/.test(event.text);
                if (!isControlChar) {
                    AskpassStore.passwordBuffer += event.text;
                }
                event.accepted = true;
            }
        }

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Appearance.padding.large

            spacing: Appearance.spacing.normal

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
                text: AskpassStore.promptMessage.replace(/:$/, "")
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
                    opacity: AskpassStore.passwordBuffer ? 0 : 1

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
                        values: AskpassStore.passwordBuffer.split("")
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

                    onClicked: AskpassStore.cancel()
                }

                TextButton {
                    id: submitButton

                    Layout.fillWidth: true
                    Layout.minimumHeight: Appearance.font.size.normal + Appearance.padding.normal * 2
                    inactiveColour: Colours.palette.m3primary
                    inactiveOnColour: Colours.palette.m3onPrimary
                    text: qsTr("Authenticate")
                    enabled: AskpassStore.passwordBuffer.length > 0

                    onClicked: AskpassStore.submitPassword(AskpassStore.passwordBuffer)
                }
            }
        }
    }
}
