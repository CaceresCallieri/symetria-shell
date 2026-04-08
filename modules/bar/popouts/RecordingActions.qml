pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import qs.modules.recorder as RecorderModule
import QtQuick
import QtQuick.Layouts

/// Popout panel for recording bar embed hover interaction.
///
/// Mode-aware: shows shared action buttons (pause, cancel, submit) for
/// both modes, plus STT-specific controls (restart, vocabulary hints)
/// when RecordingSessionManager.activeMode is "stt".
ColumnLayout {
    id: root

    readonly property string mode: RecordingSessionManager.activeMode

    // intentional var: polymorphic job (SttJob | AudioRecorderJob | null)
    readonly property var job: RecordingSessionManager.currentJob

    spacing: Appearance.spacing.normal
    implicitWidth: 280

    // ── Action buttons (hidden during Alt+W vocab mode for STT) ──
    FadeTransition {
        Layout.alignment: Qt.AlignHCenter
        show: root.job !== null
            && (root.job.state === "recording" || root.job.state === "paused")
            && !(root.mode === "stt" && SttService.vocabHintsVisible)

        RowLayout {
            spacing: Appearance.spacing.normal

            PillButton {
                id: pauseBtn

                icon: root.job?.recording ? "pause" : "play_arrow"
                iconColor: root.job?.recording ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3primary
                onClicked: {
                    if (!root.job) return;
                    if (root.mode === "stt")
                        root.job.recording ? root.job.pause() : root.job.resume();
                    else
                        AudioRecorderService.pause();
                }
            }

            // Restart (STT only)
            PillButton {
                id: restartBtn

                visible: root.mode === "stt"
                icon: "restart_alt"
                onClicked: SttService.restart()
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
                onClicked: {
                    if (root.mode === "stt")
                        root.job?.stop();
                    else
                        AudioRecorderService.stop();
                }
            }
        }
    }

    // ── Vocabulary hint chips (STT only) ──────────────────────────
    FadeTransition {
        Layout.alignment: Qt.AlignHCenter
        show: root.mode === "stt"
            && SttService.sessionVocabHints.length > 0
            && root.job !== null
            && (root.job.state === "recording" || root.job.state === "paused")

        RecorderModule.VocabHintChips {}
    }

    // ── Vocabulary hints text input (STT only) ────────────────────
    FadeTransition {
        Layout.alignment: Qt.AlignHCenter
        show: root.mode === "stt" && SttService.vocabHintsVisible && SttService.active

        RecorderModule.VocabularyHints {}
    }

    // ── Audio IPC action visual feedback ──────────────────────────
    Connections {
        target: root.mode === "audio" ? AudioRecorderService : null

        function onActionTriggered(action: string): void {
            switch (action) {
                case "pause":
                case "resume":
                    pauseBtn.triggerPress(); break;
                case "cancel":
                    cancelBtn.triggerPress(); break;
                case "stop":
                    submitBtn.triggerPress(); break;
            }
        }
    }

    // ── STT IPC action visual feedback ────────────────────────────
    Connections {
        target: root.mode === "stt" ? SttService : null

        function onActionTriggered(sessionId: string, action: string): void {
            if (!root.job) return;
            if (sessionId !== "" && sessionId !== root.job.sessionId) return;

            switch (action) {
                case "pause":
                case "resume":
                    pauseBtn.triggerPress(); break;
                case "restart":
                    restartBtn.triggerPress(); break;
                case "cancel":
                    cancelBtn.triggerPress(); break;
                case "stop":
                    submitBtn.triggerPress(); break;
            }
        }
    }
}
