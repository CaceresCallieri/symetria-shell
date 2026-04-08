pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

/// Popout panel for audio recording bar embed hover interaction.
///
/// Shows action buttons (pause, cancel, stop) when hovering over
/// the recording center embed in merge mode. Subset of SttActions
/// (no restart, no vocabulary hints).
ColumnLayout {
    id: root

    readonly property AudioRecorderJob job: AudioRecorderService.job

    spacing: Appearance.spacing.normal
    implicitWidth: 200

    // ── Action buttons ──────────────────────────────────────
    FadeTransition {
        Layout.alignment: Qt.AlignHCenter
        show: root.job !== null
            && (root.job.state === "recording" || root.job.state === "paused")

        RowLayout {
            spacing: Appearance.spacing.normal

            PillButton {
                id: pauseBtn

                icon: root.job?.state === "paused" ? "play_arrow" : "pause"
                iconColor: root.job?.state === "paused" ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                onClicked: AudioRecorderService.pause()
            }

            PillButton {
                id: cancelBtn

                icon: "close"
                iconColor: Colours.palette.m3error
                onClicked: {
                    if (root.job) root.job.cancel();
                }
            }

            PillButton {
                id: submitBtn

                icon: "check"
                iconColor: Colours.palette.m3confirm
                onClicked: AudioRecorderService.stop()
            }
        }
    }

    // ── IPC action visual feedback ─────────────────────────
    Connections {
        target: AudioRecorderService

        function onActionTriggered(action: string): void {
            switch (action) {
                case "pause":
                case "resume":
                    pauseBtn.triggerPress();
                    break;
                case "cancel":
                    cancelBtn.triggerPress();
                    break;
                case "stop":
                    submitBtn.triggerPress();
                    break;
            }
        }
    }
}
