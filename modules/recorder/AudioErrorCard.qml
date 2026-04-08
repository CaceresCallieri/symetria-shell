import qs.components
import qs.components.controls
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

/// Error state card for audio recording failures.
/// Shows error icon, message, hint, and cancel button with IPC feedback.
/// Loaded by Content.qml's terminal-state Loader via sourceComponent wrapper.
ColumnLayout {
    id: root

    required property string stateIcon
    required property color stateIconColor
    // intentional var: polymorphic job (AudioRecorderJob | null)
    required property var job
    required property string displayState

    spacing: Appearance.spacing.small

    MaterialIcon {
        Layout.alignment: Qt.AlignHCenter
        text: root.stateIcon
        color: root.stateIconColor
        font.pointSize: Appearance.font.size.extraLarge
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        text: root.job?.errorDetail ?? qsTr("Recording failed")
        font.pointSize: Appearance.font.size.normal
        color: Colours.palette.m3error
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        text: root.job?.errorHint ?? qsTr("Check audio configuration")
        font.pointSize: Appearance.font.size.small
        color: Colours.palette.m3outline
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Appearance.spacing.normal

        PillButton {
            id: cancelBtn
            icon: "close"
            iconColor: Colours.palette.m3error
            onClicked: root.job?.cancel()
        }
    }

    Connections {
        target: AudioRecorderService

        function onActionTriggered(action: string): void {
            if (root.displayState !== "error") return;
            if (action === "cancel") cancelBtn.triggerPress();
        }
    }
}
