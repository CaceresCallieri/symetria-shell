pragma ComponentBehavior: Bound

import qs.services
import qs.config
import Quickshell
import Quickshell.Io
import QtQuick

/// Root component for audio recorder drawer.
///
/// Auto-shows the drawer on all screens when AudioRecorderService becomes active.
/// Exposes IPC handler for control (toggle, start, stop, pause, cancel).
Scope {
    Connections {
        target: AudioRecorderService

        function onActiveChanged(): void {
            if (!Config.audioRecorder.enabled)
                return;

            for (const [_, visibilities] of Visibilities.screens)
                visibilities.audioRecorder = AudioRecorderService.active;
        }
    }

    IpcHandler {
        target: "audio"

        function toggle(): void {
            AudioRecorderService.toggle();
        }
        function start(): void {
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
}
