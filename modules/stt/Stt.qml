pragma ComponentBehavior: Bound

import qs.services
import qs.config
import Quickshell
import Quickshell.Io
import QtQuick

/// Root component for native speech-to-text drawer.
///
/// Auto-shows the drawer on all screens when SttService becomes active.
/// When AgentService.mergeActive is true, the bar center embed handles
/// display instead — drawer visibility is suppressed.
/// Exposes IPC handler for control (start, stop, pause, cancel, etc.).
Scope {
    Connections {
        target: SttService

        function onActiveChanged(): void {
            if (!Config.stt.enabled)
                return;

            // Bar embed handles display when merge mode is active
            if (AgentService.mergeActive)
                return;

            for (const [_, visibilities] of Visibilities.screens)
                visibilities.stt = SttService.active;
        }
    }

    // Handle merge mode toggling mid-recording.
    // When merge activates: close drawer (bar embed takes over).
    // When merge deactivates: open drawer (bar embed disappears).
    Connections {
        target: AgentService

        function onMergeActiveChanged(): void {
            if (!Config.stt.enabled || !SttService.active)
                return;

            for (const [_, visibilities] of Visibilities.screens)
                visibilities.stt = !AgentService.mergeActive;
        }
    }

    IpcHandler {
        target: "stt"

        function toggle(): void {
            SttService.toggle();
        }
        function start(): void {
            SttService.start();
        }
        function stop(): void {
            SttService.stop();
        }
        function pause(): void {
            SttService.pause();
        }
        function resume(): void {
            SttService.resume();
        }
        function cancel(): void {
            SttService.cancel();
        }
        function restart(): void {
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
    }
}
