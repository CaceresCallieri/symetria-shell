pragma ComponentBehavior: Bound

import "services"
import qs.components
import qs.components.controls
import qs.components.containers
import qs.components.misc
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

    implicitWidth: dialog.implicitWidth
    implicitHeight: dialog.implicitHeight + padding

    FocusManager {
        active: root.visibilities.askpass
        target: dialog
    }

    // Dialog container. Switched from StyledRect (transparent) to Item +
    // PillCard backdrop so the prompt/password/buttons read against a warm
    // claymorphism panel instead of floating directly on the wallpaper.
    // Mirrors the RecordingBarEmbed treatment — same two-tier hierarchy:
    // PillCard (m3surfaceContainerLow) hosts the inner password pill
    // (m3surfaceContainer) so the field protrudes from the card frame.
    Item {
        id: dialog

        anchors.top: parent.top
        anchors.topMargin: root.padding
        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth: 350
        implicitHeight: content.implicitHeight + Appearance.padding.normal * 2

        readonly property bool showButtons: dialogHover.hovered

        // Claymorphism backdrop. Default fill (m3surfaceContainerLow) +
        // default radius (rounding.normal) intentional: this is a section
        // card, not a capsule pill, so we want the warmer rim/inner-shadow
        // recipe that PillCard's defaults already encode.
        PillCard {
            anchors.fill: parent
        }

        HoverHandler {
            id: dialogHover
        }

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
            } else if (event.text && event.text.length > 0) {
                // Filter out control characters (0x00-0x1F and 0x7F)
                // This prevents Tab, Ctrl sequences, etc. from entering password
                const isControlChar = event.key === Qt.Key_Tab || /[\x00-\x1F\x7F]/.test(event.text);
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
            anchors.top: parent.top
            anchors.margins: Appearance.padding.normal
            // Extra horizontal breathing room so the password pill and button
            // row don't crowd the PillCard's rim. Vertical stays normal because
            // the dialog's implicitHeight bakes padding.normal * 2 (line 44).
            anchors.leftMargin: Appearance.padding.large
            anchors.rightMargin: Appearance.padding.large

            spacing: Appearance.spacing.normal

            // Prompt message from sudo
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: AskpassStore.promptMessage.replace(/:$/, "")
                color: Colours.palette.m3outline
                font.pointSize: Appearance.font.size.small
            }

            // Command being authenticated (if available)
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: parent.width - Appearance.padding.large * 2
                visible: AskpassStore.commandInfo !== ""
                text: AskpassStore.commandInfo
                color: Colours.palette.m3tertiary
                font.pointSize: Appearance.font.size.small
                font.family: Appearance.font.family.mono
                elide: Text.ElideMiddle
                maximumLineCount: 1
            }

            // Password input container
            Item {
                id: passwordContainer

                Layout.topMargin: Appearance.spacing.small
                Layout.fillWidth: true
                implicitHeight: Math.max(36, charList.implicitHeight + Appearance.padding.smaller * 2)

                StyledRect {
                    anchors.fill: parent
                    radius: Appearance.rounding.normal
                    color: dialog.activeFocus ? Qt.lighter(Colours.tPalette.m3surfaceContainer, 1.05) : Colours.tPalette.m3surfaceContainer
                    border.width: 1
                    border.color: dialog.activeFocus ? Colours.palette.m3primary : Colours.palette.m3outline

                    Behavior on border.color {
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

            // Buttons (hover-revealed matte pills)
            RowLayout {
                id: buttonRow

                Layout.topMargin: Appearance.spacing.small
                Layout.fillWidth: true
                Layout.preferredHeight: dialog.showButtons ? implicitHeight : 0
                spacing: Appearance.spacing.normal
                clip: true

                opacity: dialog.showButtons ? 1 : 0
                transform: Translate {
                    y: dialog.showButtons ? 0 : 8
                    Behavior on y {
                        Anim {
                            duration: Appearance.anim.durations.small
                            easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
                        }
                    }
                }

                Behavior on opacity {
                    Anim {
                        duration: Appearance.anim.durations.small
                    }
                }

                Behavior on Layout.preferredHeight {
                    Anim {
                        duration: Appearance.anim.durations.small
                        easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
                    }
                }

                // Cancel pill
                Item {
                    id: cancelPill

                    Layout.fillWidth: true
                    implicitHeight: cancelLabel.implicitHeight + Appearance.padding.smaller * 2

                    readonly property var style: Colours.pillStyle(
                        Colours.palette.m3surfaceContainerHigh,
                        cancelState.containsMouse ? Colours.glass.medium : Colours.glass.subtle
                    )

                    StyledRect {
                        anchors.fill: parent
                        radius: Appearance.rounding.full
                        color: cancelPill.style.background
                        border.width: 1
                        border.color: cancelPill.style.border

                        Behavior on color {
                            CAnim {}
                        }

                        Behavior on border.color {
                            CAnim {}
                        }
                    }

                    StateLayer {
                        id: cancelState

                        radius: Appearance.rounding.full
                        color: Colours.palette.m3onSurfaceVariant

                        function onClicked(): void {
                            AskpassStore.cancel();
                        }
                    }

                    StyledText {
                        id: cancelLabel

                        anchors.centerIn: parent
                        text: qsTr("Cancel")
                        color: Colours.palette.m3onSurfaceVariant
                        font.pointSize: Appearance.font.size.small
                    }
                }

                // Authenticate pill
                Item {
                    id: authPill

                    Layout.fillWidth: true
                    implicitHeight: authLabel.implicitHeight + Appearance.padding.smaller * 2
                    opacity: enabled ? 1.0 : 0.38 // M3 disabled state opacity
                    enabled: AskpassStore.passwordBuffer.length > 0

                    readonly property var style: Colours.pillStyle(
                        Colours.palette.m3surfaceContainerHigh,
                        authState.containsMouse ? Colours.glass.medium : Colours.glass.subtle
                    )

                    StyledRect {
                        anchors.fill: parent
                        radius: Appearance.rounding.full
                        color: authPill.style.background
                        border.width: 1
                        border.color: authPill.style.border

                        Behavior on color {
                            CAnim {}
                        }

                        Behavior on border.color {
                            CAnim {}
                        }
                    }

                    StateLayer {
                        id: authState

                        radius: Appearance.rounding.full
                        color: Colours.palette.m3onSurfaceVariant
                        disabled: !authPill.enabled

                        function onClicked(): void {
                            AskpassStore.submitPassword(AskpassStore.passwordBuffer);
                        }
                    }

                    StyledText {
                        id: authLabel

                        anchors.centerIn: parent
                        text: qsTr("Authenticate")
                        color: Colours.palette.m3onSurfaceVariant
                        font.pointSize: Appearance.font.size.small
                    }

                    Behavior on opacity {
                        Anim {}
                    }
                }
            }
        }
    }
}
