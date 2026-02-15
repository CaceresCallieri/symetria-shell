pragma ComponentBehavior: Bound

import qs.services
import qs.config
import Quickshell
import Quickshell.Io
import QtQuick

/// Root component for HyprWhspr speech-to-text drawer.
///
/// Auto-shows the drawer on all screens when HyprWhsprService becomes active.
/// Exposes IPC handler for orchestrator control (start, stop, pause, cancel, etc.).
Scope {
    Connections {
        target: HyprWhsprService

        function onActiveChanged(): void {
            if (!Config.hyprwhspr.enabled)
                return;

            if (HyprWhsprService.active) {
                for (const [_, visibilities] of Visibilities.screens) {
                    visibilities.hyprwhspr = true;
                }
            } else {
                for (const [_, visibilities] of Visibilities.screens) {
                    visibilities.hyprwhspr = false;
                }
            }
        }
    }

    IpcHandler {
        target: "hyprwhspr"

        function toggle(lang: string): void {
            HyprWhsprService.toggle(lang);
        }
        function start(lang: string): void {
            HyprWhsprService.start(lang);
        }
        function stop(): void {
            HyprWhsprService.stop();
        }
        function pause(): void {
            HyprWhsprService.pause();
        }
        function resume(): void {
            HyprWhsprService.resume();
        }
        function cancel(): void {
            HyprWhsprService.cancel();
        }
        function restart(): void {
            HyprWhsprService.restart();
        }
    }
}
