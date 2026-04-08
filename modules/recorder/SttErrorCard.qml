import qs.components
import qs.components.controls
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

/// Error state card for STT transcription failures.
/// Shows error icon, message, hint, retry/cancel/copy buttons, and IPC feedback.
/// Loaded by Content.qml's terminal-state Loader via sourceComponent wrapper.
ColumnLayout {
    id: root

    required property string stateIcon
    required property color stateIconColor
    // intentional var: polymorphic job (SttJob | null)
    required property var job
    required property string displayState
    required property string errorSource
    required property string errorRaw

    spacing: Appearance.spacing.small

    MaterialIcon {
        Layout.alignment: Qt.AlignHCenter
        text: root.stateIcon
        color: root.stateIconColor
        font.pointSize: Appearance.font.size.extraLarge
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        text: root.job?.errorDetail ?? qsTr("Transcription failed")
        font.pointSize: Appearance.font.size.normal
        color: Colours.palette.m3error
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        text: root.job?.errorHint ?? qsTr("Check STT configuration")
        font.pointSize: Appearance.font.size.small
        color: Colours.palette.m3outline
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Appearance.spacing.normal

        PillButton {
            id: retryBtn
            visible: root.errorSource === "api" || root.errorSource === "timeout"
            icon: "refresh"
            iconColor: Colours.palette.m3primary
            onClicked: root.job?.retry()
        }

        PillButton {
            id: cancelBtn
            icon: "close"
            iconColor: Colours.palette.m3error
            onClicked: root.job?.cancel()
        }

        PillButton {
            visible: root.errorRaw !== ""
            icon: "content_copy"
            onClicked: Quickshell.execDetached(["wl-copy", root.errorRaw])
        }
    }

    // Safe: unconditional connection is correct — this card is only
    // instantiated when mode === "stt" (see Content.qml Loader selection).
    Connections {
        target: SttService

        function onActionTriggered(sessionId: string, action: string): void {
            if (sessionId !== "" && sessionId !== root.job?.sessionId) return;
            if (root.displayState !== "error") return;
            if (action === "retry") retryBtn.triggerPress();
            else if (action === "cancel") cancelBtn.triggerPress();
        }
    }
}
