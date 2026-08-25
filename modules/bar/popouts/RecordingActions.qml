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
        show: root.job !== null && (root.job.state === "recording" || root.job.state === "paused") && !(root.mode === "stt" && SttService.vocabHintsVisible)

        // Mirror of the drawer's hover-row action buttons (Content.qml). Same
        // raised Tonal IconButton aesthetic so the same logical control reads
        // identically whether the user is in merge mode (this popout) or
        // non-merge mode (the drawer's expanded row). triggerPress() works
        // because it was ported into IconButton; inactiveOnColour replaces
        // the prior PillButton.iconColor API.
        RowLayout {
            spacing: Appearance.spacing.normal

            IconButton {
                id: pauseBtn

                icon: root.job?.recording ? "pause" : "play_arrow"
                type: IconButton.Tonal
                toggle: false
                raised: true
                inactiveOnColour: root.job?.recording ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3primary
                onClicked: {
                    if (!root.job)
                        return;
                    if (root.mode === "stt")
                        root.job.recording ? root.job.pause() : root.job.resume();
                    else
                        AudioRecorderService.pause();
                }
            }

            // Restart (STT only)
            IconButton {
                id: restartBtn

                visible: root.mode === "stt"
                icon: "restart_alt"
                type: IconButton.Tonal
                toggle: false
                raised: true
                onClicked: SttService.restart()
            }

            IconButton {
                id: cancelBtn

                icon: "close"
                type: IconButton.Tonal
                toggle: false
                raised: true
                inactiveOnColour: Colours.palette.m3error
                onClicked: {
                    // Route through the service so SttService.cancel() clears
                    // _sessionVocabHints / vocabHintsVisible and emits
                    // actionTriggered (button animation). Direct job.cancel()
                    // bypasses all of that.
                    RecordingSessionManager.routeAction("cancel");
                }
            }

            IconButton {
                id: submitBtn

                icon: "check"
                type: IconButton.Tonal
                toggle: false
                raised: true
                inactiveOnColour: Colours.palette.m3confirm
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
        show: root.mode === "stt" && SttService.sessionVocabHints.length > 0 && root.job !== null && (root.job.state === "recording" || root.job.state === "paused")

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
                pauseBtn.triggerPress();
                break;
            case "cancel":
                if (root.job?.state !== "error")
                    cancelBtn.triggerPress();
                break;
            case "stop":
                submitBtn.triggerPress();
                break;
            }
        }
    }

    // ── STT IPC action visual feedback ────────────────────────────
    Connections {
        target: root.mode === "stt" ? SttService : null

        function onActionTriggered(sessionId: string, action: string): void {
            if (!root.job)
                return;
            if (sessionId !== "" && sessionId !== root.job.sessionId)
                return;

            switch (action) {
            case "pause":
            case "resume":
                pauseBtn.triggerPress();
                break;
            case "restart":
                restartBtn.triggerPress();
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
