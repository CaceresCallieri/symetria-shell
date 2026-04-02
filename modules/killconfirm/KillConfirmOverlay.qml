pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.containers
import qs.components.misc
import qs.services
import qs.config
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

/// Kill-window confirmation overlay on WlrLayer.Overlay.
///
/// Centered on screen. Shows the window title/class and two actions:
/// Enter to confirm force-kill, Escape to cancel.
/// Uses the same layer-shell pattern as KeyChordsOverlay for fullscreen visibility.
Scope {
    id: root

    /// Reference to the KillConfirm IPC handler — set from shell.qml via the id.
    required property KillConfirm handler

    Variants {
        model: Quickshell.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData

            screen: modelData
            name: "killconfirm-overlay"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            visible: win.shouldShow || win.dialogOpacity > 0

            mask: inputRegion

            Region {
                id: inputRegion
                x: 0
                y: 0
                width: win.shouldShow ? win.width : 0
                height: win.shouldShow ? win.height : 0
            }

            readonly property bool shouldShow: root.handler.active && root.handler.targetMonitor === Hypr.monitorFor(modelData)

            property real dialogOpacity: shouldShow ? 1.0 : 0.0
            property real dialogScale: shouldShow ? 1.0 : 0.0

            Behavior on dialogOpacity {
                NumberAnimation {
                    duration: Appearance.anim.durations.normal * 0.75
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on dialogScale {
                NumberAnimation {
                    duration: Appearance.anim.durations.large * 0.75
                    easing.type: Easing.OutBack
                }
            }

            FocusManager {
                active: win.shouldShow
                target: dialog
            }

            // Click outside → dismiss
            MouseArea {
                anchors.fill: parent
                visible: win.dialogOpacity > 0
                enabled: win.shouldShow
                onClicked: root.handler.dismiss()
            }

            // Centered dialog — scales from 0 with overshoot
            Item {
                id: dialogWrapper

                anchors.centerIn: parent
                width: dialog.implicitWidth
                height: dialog.implicitHeight

                scale: win.dialogScale
                opacity: win.dialogOpacity

                StyledRect {
                    id: dialog

                    implicitWidth: dialogContent.implicitWidth + Appearance.padding.large * 2
                    implicitHeight: dialogContent.implicitHeight + Appearance.padding.large * 2

                    readonly property var glassStyle: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)

                    radius: Appearance.rounding.normal
                    color: glassStyle.background
                    border.width: 1
                    border.color: glassStyle.border

                    focus: true

                    Keys.onReturnPressed: event => {
                        event.accepted = true;
                        root.handler.confirm();
                    }

                    Keys.onEnterPressed: event => {
                        event.accepted = true;
                        root.handler.confirm();
                    }

                    Keys.onEscapePressed: event => {
                        event.accepted = true;
                        root.handler.dismiss();
                    }

                    ColumnLayout {
                        id: dialogContent

                        anchors.centerIn: parent
                        spacing: Appearance.spacing.normal

                        // Warning icon
                        MaterialIcon {
                            Layout.alignment: Qt.AlignHCenter
                            text: "warning"
                            font.pointSize: Appearance.font.size.larger * 1.5
                            color: Colours.palette.m3error
                        }

                        // Title
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("Force kill window?")
                            font.pointSize: Appearance.font.size.normal
                            font.weight: Font.DemiBold
                            color: Colours.palette.m3onSurface
                        }

                        // Window info
                        ColumnLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: Appearance.spacing.smaller

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.maximumWidth: 400
                                text: root.handler.windowTitle || qsTr("Unknown window")
                                font.pointSize: Appearance.font.size.small
                                color: Colours.palette.m3onSurfaceVariant
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                            }

                            StyledText {
                                visible: root.handler.windowClass !== ""
                                Layout.alignment: Qt.AlignHCenter
                                text: root.handler.windowClass
                                font.pointSize: Appearance.font.size.smaller
                                color: Colours.palette.m3outline
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        // Warning description
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: 350
                            text: qsTr("This sends SIGTERM and may close all instances of the application. Unsaved work will be lost.")
                            font.pointSize: Appearance.font.size.smaller
                            color: Colours.palette.m3onSurfaceVariant
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }

                        // Action buttons
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: Appearance.spacing.normal

                            PillButton {
                                icon: "close"
                                text: qsTr("Cancel")
                                onClicked: root.handler.dismiss()
                            }

                            PillButton {
                                icon: "delete_forever"
                                text: qsTr("Kill")
                                pillColor: Colours.palette.m3error
                                iconColor: Colours.palette.m3error
                                onClicked: root.handler.confirm()
                            }
                        }

                        // Hint
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("Enter to confirm · Escape to cancel")
                            font.pointSize: Appearance.font.size.smallest
                            color: Colours.palette.m3outline
                        }
                    }
                }
            }
        }
    }
}
