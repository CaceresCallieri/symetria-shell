pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import Quickshell
import QtQuick

/// Animated password input with dot visualization.
///
/// Manages its own key handling (typing, backspace, Ctrl+Backspace, Enter),
/// focus lifecycle, and displays each character as an animated dot in a
/// horizontal ListView.  Extracted from WirelessPassword.qml.
FocusScope {
    id: root

    property string password: ""
    property bool hasError: false
    property bool isActive: false

    signal submitted()
    signal errorCleared()

    implicitHeight: Math.max(48, charList.implicitHeight + Appearance.padding.normal * 2)

    focus: true
    activeFocusOnTab: true

    Keys.onPressed: event => {
        if (!activeFocus) {
            forceActiveFocus();
        }

        if (hasError && event.text && event.text.length > 0) {
            hasError = false;
            errorCleared();
        }

        if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
            submitted();
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace) {
            if (event.modifiers & Qt.ControlModifier) {
                password = "";
            } else {
                password = password.slice(0, -1);
            }
            event.accepted = true;
        } else if (event.text && event.text.length > 0) {
            password += event.text;
            event.accepted = true;
        }
    }

    Connections {
        target: root

        function onIsActiveChanged(): void {
            if (root.isActive) {
                _focusTimer.start();
                root.password = "";
            }
        }
    }

    Timer {
        id: _focusTimer

        interval: 50
        onTriggered: root.forceActiveFocus()
    }

    Component.onCompleted: {
        if (isActive)
            _focusTimer.start();
    }

    // --- Visual: background rectangle with focus/error border ---

    StyledRect {
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: root.activeFocus ? Qt.lighter(Colours.tPalette.m3surfaceContainer, 1.05) : Colours.tPalette.m3surfaceContainer
        border.width: root.activeFocus || root.hasError ? 4 : (root.isActive ? 1 : 0)
        border.color: {
            if (root.hasError)
                return Colours.palette.m3error;
            if (root.activeFocus)
                return Colours.palette.m3primary;
            return root.isActive ? Colours.palette.m3outline : "transparent";
        }

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
        radius: Appearance.rounding.normal

        function onClicked(): void {
            root.forceActiveFocus();
        }
    }

    // --- Placeholder ---

    StyledText {
        anchors.centerIn: parent
        text: qsTr("Password")
        color: Colours.palette.m3outline
        font.pointSize: Appearance.font.size.normal
        font.family: Appearance.font.family.mono
        opacity: root.password ? 0 : 1

        Behavior on opacity {
            Anim {}
        }
    }

    // --- Character dot visualization ---

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
            values: root.password.split("")
        }

        delegate: StyledRect {
            id: ch

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
            ListView.onRemove: _removeAnim.start()

            SequentialAnimation {
                id: _removeAnim

                PropertyAction {
                    target: ch
                    property: "ListView.delayRemove"
                    value: true
                }
                ParallelAnimation {
                    Anim {
                        target: ch
                        property: "opacity"
                        to: 0
                    }
                    Anim {
                        target: ch
                        property: "scale"
                        to: 0.5
                    }
                }
                PropertyAction {
                    target: ch
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
