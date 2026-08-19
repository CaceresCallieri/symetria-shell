pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import Quickshell
import QtQuick

/// Animated password input with dot visualization.
///
/// Manages its own key handling (typing, backspace, Ctrl+Backspace, Enter,
/// Ctrl+H), focus lifecycle, and masked or visible password rendering.
/// Extracted from WirelessPassword.qml.
FocusScope {
    id: root

    property alias password: editor.text
    property bool hasError: false
    property bool isActive: false
    property bool passwordVisible: false
    property bool cancelOnEscape: false
    property string placeholderText: qsTr("Password")
    readonly property real caretGap: Appearance.spacing.small / 2
    readonly property real passwordContentWidth: Math.max(0, width
        - revealButton.implicitWidth * 2
        - focusCaret.implicitWidth * 2
        - Appearance.padding.normal * 2
        - Appearance.spacing.small * 2)

    signal submitted()
    signal errorCleared()
    signal cancelled()

    implicitHeight: Math.max(48, charList.implicitHeight + Appearance.padding.normal * 2)

    focus: true

    function togglePasswordVisibility(): void {
        passwordVisible = !passwordVisible;
        if (!passwordVisible)
            editor.cursorPosition = editor.text.length;
        editor.forceActiveFocus();
    }

    onIsActiveChanged: {
        if (isActive) {
            editor.clear();
            _focusTimer.start();
        } else {
            _focusTimer.stop();
            editor.clear();
            passwordVisible = false;
        }
    }

    Timer {
        id: _focusTimer

        interval: 50
        onTriggered: {
            if (root.isActive)
                editor.forceActiveFocus();
        }
    }

    Component.onCompleted: {
        if (isActive)
            _focusTimer.start();
    }

    TextInput {
        id: editor

        anchors.centerIn: parent
        width: root.passwordContentWidth
        focus: root.isActive
        activeFocusOnTab: true
        z: 1
        color: root.passwordVisible ? Colours.palette.m3onSurface : "transparent"
        selectionColor: root.passwordVisible ? Colours.palette.m3primary : "transparent"
        selectedTextColor: root.passwordVisible ? Colours.palette.m3onPrimary : "transparent"
        cursorVisible: root.passwordVisible && activeFocus
        echoMode: root.passwordVisible ? TextInput.Normal : TextInput.Password
        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
        horizontalAlignment: TextInput.AlignHCenter
        verticalAlignment: TextInput.AlignVCenter
        font.family: Appearance.font.family.mono
        font.pointSize: Appearance.font.size.normal
        clip: true

        Accessible.role: Accessible.EditableText
        Accessible.name: root.placeholderText || qsTr("Password")
        Accessible.passwordEdit: true

        onAccepted: root.submitted()
        onCursorPositionChanged: {
            if (!root.passwordVisible && cursorPosition !== text.length)
                cursorPosition = text.length;
        }
        onTextChanged: {
            if (!root.passwordVisible && cursorPosition !== text.length)
                cursorPosition = text.length;
        }
        onTextEdited: {
            if (root.hasError) {
                root.hasError = false;
                root.errorCleared();
            }
        }

        Keys.onPressed: event => {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_H) {
                root.togglePasswordVisibility();
                event.accepted = true;
                return;
            }

            if (event.key === Qt.Key_Escape) {
                if (root.cancelOnEscape) {
                    root.cancelled();
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
                return;
            }

            if (!root.passwordVisible
                    && (event.key === Qt.Key_Left
                        || event.key === Qt.Key_Right
                        || event.key === Qt.Key_Home
                        || event.key === Qt.Key_End
                        || event.key === Qt.Key_Up
                        || event.key === Qt.Key_Down
                        || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_A))) {
                event.accepted = true;
            }
        }
    }

    // An input well is permanently inset. Focus and error state change its
    // edge colour without introducing another surface dialect.

    PillToggleSurface {
        anchors.fill: parent
        active: true
        activeColor: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle).background
        borderColor: root.hasError ? Colours.palette.m3error : root.activeFocus ? Colours.palette.m3primary : Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle).border
        radius: Appearance.rounding.normal
    }

    StateLayer {
        z: 2
        visible: !root.passwordVisible
        hoverEnabled: false
        cursorShape: Qt.IBeamCursor
        radius: Appearance.rounding.normal

        function onClicked(): void {
            editor.forceActiveFocus();
        }
    }

    // --- Placeholder ---

    StyledText {
        id: placeholder

        anchors.centerIn: parent
        text: root.placeholderText
        color: Colours.palette.m3outline
        font.pointSize: Appearance.font.size.normal
        font.family: Appearance.font.family.mono
        opacity: root.password || !text ? 0 : 1

        Behavior on opacity {
            Anim {}
        }
    }

    // --- Character dot visualization ---

    ListView {
        id: charList

        readonly property int fullWidth: Math.max(0, count * (implicitHeight + spacing) - spacing)

        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.activeFocus && root.password.length > 0
            ? -(focusCaret.implicitWidth + root.caretGap) / 2
            : 0
        visible: !root.passwordVisible
        implicitWidth: Math.min(fullWidth, root.passwordContentWidth)
        implicitHeight: Appearance.font.size.normal

        orientation: Qt.Horizontal
        spacing: Appearance.spacing.small / 2
        interactive: false
        contentX: Math.max(0, contentWidth - width)
        clip: true

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

        Behavior on anchors.horizontalCenterOffset {
            Anim {}
        }
    }

    Rectangle {
        id: focusCaret

        anchors.verticalCenter: parent.verticalCenter
        z: 3
        implicitWidth: 2
        implicitHeight: Appearance.font.size.normal

        function restartBlink(): void {
            caretBlink.stop();
            opacity = 1;
            if (visible)
                caretBlink.start();
        }

        x: {
            let desiredX;
            if (root.password.length === 0) {
                desiredX = root.placeholderText
                    ? placeholder.x + (placeholder.width + placeholder.paintedWidth) / 2 + root.caretGap
                    : (root.width - implicitWidth) / 2;
            } else {
                desiredX = charList.x + charList.width + root.caretGap;
            }
            return Math.min(desiredX, revealButton.x - implicitWidth - Appearance.spacing.small);
        }
        visible: root.activeFocus && !root.passwordVisible
        color: Colours.palette.m3primary
        radius: width / 2

        SequentialAnimation on opacity {
            id: caretBlink

            loops: Animation.Infinite

            NumberAnimation {
                to: 0.15
                duration: 500
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                to: 1
                duration: 500
                easing.type: Easing.InOutSine
            }
        }

        onVisibleChanged: restartBlink()
        Component.onCompleted: restartBlink()

        Connections {
            target: root

            function onPasswordChanged(): void {
                focusCaret.restartBlink();
            }
        }
    }

    IconButton {
        id: revealButton

        anchors.right: parent.right
        anchors.rightMargin: Appearance.padding.small
        anchors.verticalCenter: parent.verticalCenter
        z: 3
        toggle: true
        checked: root.passwordVisible
        icon: root.passwordVisible ? "visibility_off" : "visibility"
        type: IconButton.Tonal
        padding: Appearance.padding.small

        onClicked: root.togglePasswordVisibility()
    }

    Tooltip {
        target: revealButton
        text: root.passwordVisible ? qsTr("Hide password (Ctrl+H)") : qsTr("Show password (Ctrl+H)")
    }
}
