pragma ComponentBehavior: Bound

import qs.services
import qs.config
import Quickshell
import Quickshell.Io
import QtQuick

/// Root component for native speech-to-text drawer.
///
/// Auto-shows the drawer on all screens when SttService becomes active.
/// Exposes IPC handler for control (start, stop, pause, cancel, etc.).
Scope {
    Connections {
        target: SttService

        function onActiveChanged(): void {
            if (!Config.stt.enabled)
                return;

            if (SttService.active) {
                for (const [_, visibilities] of Visibilities.screens) {
                    visibilities.stt = true;
                }
            } else {
                for (const [_, visibilities] of Visibilities.screens) {
                    visibilities.stt = false;
                }
            }
        }
    }

    IpcHandler {
        target: "stt"

        function toggle(lang: string): void {
            SttService.toggle(lang);
        }
        function start(lang: string): void {
            SttService.start(lang);
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
    }
}
