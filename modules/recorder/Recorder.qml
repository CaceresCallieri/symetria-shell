pragma ComponentBehavior: Bound

import qs.services
import qs.config
import Quickshell
import Quickshell.Io
import QtQuick

/// Root component for the unified recorder module.
///
/// Handles two IPC targets:
///   - "audio": audio recorder specific (toggle/start/stop/pause/cancel)
///   - "recorder": shared actions routed to whichever mode is active
///
/// Manages drawer visibility across all screens with merge mode awareness:
/// when AgentService.mergeActive is true, the bar embed takes over and the
/// drawer hides (same handoff pattern as STT).
Scope {
    // ── Audio Recorder visibility sync ────────────────────────────

    Connections {
        target: AudioRecorderService

        function onActiveChanged(): void {
            if (!Config.audioRecorder.enabled)
                return;

            // Bar embed handles display when merge mode is active
            if (AgentService.mergeActive)
                return;

            for (const [_, visibilities] of Visibilities.screens)
                visibilities.recorder = AudioRecorderService.active;
        }
    }

    // Handle merge mode toggling mid-recording.
    // When merge activates: close drawer (bar embed takes over).
    // When merge deactivates: reopen drawer.
    Connections {
        target: AgentService

        function onMergeActiveChanged(): void {
            if (!Config.audioRecorder.enabled || !AudioRecorderService.active)
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
