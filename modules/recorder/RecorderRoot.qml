pragma ComponentBehavior: Bound

import qs.services
import qs.config
import Quickshell
import Quickshell.Io
import QtQuick

/// Root component for the unified recorder module.
///
/// Handles three IPC targets:
///   - "audio": audio recorder specific (toggle/start/stop/pause/cancel)
///   - "stt": speech-to-text specific (toggle/start/stop/pause/resume/cancel/restart/retry/mode/hints)
///   - "recorder": shared actions routed to whichever mode is active
///
/// Manages drawer visibility across all screens with merge mode awareness:
/// when AgentService.mergeActive is true, the bar embed takes over and the
/// drawer hides.
///
/// Named RecorderRoot (not Recorder) to avoid type-name collision with
/// services/Recorder.qml (the screen-recorder singleton). Both names
/// resolve to "Recorder" in QML and the last import wins.
Scope {
    // ── Audio Recorder visibility sync ────────────────────────────

    Connections {
        target: AudioRecorderService

        function onActiveChanged(): void {
            if (!Config.audioRecorder.enabled)
                return;
            if (AgentService.mergeActive)
                return;

            for (const [_, visibilities] of Visibilities.screens)
                visibilities.recorder = AudioRecorderService.active;
        }
    }

    // ── STT visibility sync ──────────────────────────────────────

    Connections {
        target: SttService

        function onActiveChanged(): void {
            if (!Config.stt.enabled)
                return;
            if (AgentService.mergeActive)
                return;

            for (const [_, visibilities] of Visibilities.screens)
                visibilities.recorder = SttService.active;
        }
    }

    // ── Merge mode handoff (unified for both modes) ──────────────
    // When merge activates: close drawer (bar embed takes over).
    // When merge deactivates: reopen drawer.

    Connections {
        target: AgentService

        function onMergeActiveChanged(): void {
            if (!RecordingSessionManager.active)
                return;

            for (const [_, visibilities] of Visibilities.screens)
                visibilities.recorder = !AgentService.mergeActive;
        }
    }

    // ── IPC: "audio" target (audio recorder specific) ─────────────

    IpcHandler {
        target: "audio"

        function toggle(): void {
            if (!RecordingSessionManager.acquire("audio")) return;
            AudioRecorderService.toggle();
        }

        function start(): void {
            if (!RecordingSessionManager.acquire("audio")) return;
            AudioRecorderService.start();
        }

        function stop(): void {
            AudioRecorderService.stop();
        }

        function pause(): void {
            AudioRecorderService.pause();
        }

        function cancel(): void {
            AudioRecorderService.cancel();
        }
    }

    // ── IPC: "stt" target (speech-to-text specific) ──────────────

    IpcHandler {
        target: "stt"

        function toggle(): void {
            if (!RecordingSessionManager.acquire("stt")) return;
            SttService.toggle();
        }

        function start(): void {
            if (!RecordingSessionManager.acquire("stt")) return;
            SttService.start();
        }

        function stop(): void {
            SttService.stop();
        }

        function pause(): void {
            SttService.pause();
        }

        // resume routes through pause(), which handles both directions
        // (recording→paused and paused→recording) and emits actionTriggered.
        function resume(): void {
            SttService.pause();
        }

        function cancel(): void {
            SttService.cancel();
        }

        function restart(): void {
            // Guard before acquire: with no active session (e.g. a stale
            // session-scoped Alt+R bind after a crash), acquire() would take
            // the "stt" lock and nothing would ever release it — release only
            // fires on SttService.active true→false.
            if (!SttService.active) return;
            if (!RecordingSessionManager.acquire("stt")) return;
            SttService.restart();
        }

        function retry(): void {
            SttService.retry();
        }

        function mode(choice: string): void {
            SttService.setDeliveryChoice(choice);
        }

        function hints(): void {
            SttService.toggleVocabHints();
        }

        // Copy the most recent transcription to the clipboard so the user
        // can paste it instantly with Ctrl+V (cliphist scrub keeps the entry
        // out of the Text tab). Wired to Alt+V in the Hyprland keybinds —
        // fast-path "grab latest dictation" without opening the clipboard
        // manager. For a specific older entry, the user opens the manager
        // and presses Enter on the highlighted row.
        function pasteTranscription(): void {
            TranscriptionStore.paste("");
        }

        // Toggle streaming dictation mode (Super+Alt+D). Switches subsequent
        // recordings between streaming (live partials) and batch, and drives
        // the bar's dictation-status icon while active.
        function streamingToggle(): void {
            SttService.toggleStreaming();
        }
    }

    // ── IPC: "recorder" target (shared actions) ───────────────────

    IpcHandler {
        target: "recorder"

        function pause(): void {
            RecordingSessionManager.routeAction("pause");
        }

        function cancel(): void {
            RecordingSessionManager.routeAction("cancel");
        }

        function stop(): void {
            RecordingSessionManager.routeAction("stop");
        }
    }
}
