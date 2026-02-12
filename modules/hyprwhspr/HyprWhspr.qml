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
                console.log("HyprWhspr: Drawer shown");
            } else {
                for (const [_, visibilities] of Visibilities.screens) {
                    visibilities.hyprwhspr = false;
                }
                console.log("HyprWhspr: Drawer hidden");
            }
        }
    }

    IpcHandler {
        target: "hyprwhspr"

        function toggle(lang: string): void {
            console.log("[HW IPC] → toggle('" + lang + "')");
            HyprWhsprService.toggle(lang);
        }
        function start(lang: string): void {
            console.log("[HW IPC] → start('" + lang + "')");
            HyprWhsprService.start(lang);
        }
        function stop(): void {
            console.log("[HW IPC] → stop()");
            HyprWhsprService.stop();
        }
        function pause(): void {
            console.log("[HW IPC] → pause()");
            HyprWhsprService.pause();
        }
        function resume(): void {
            console.log("[HW IPC] → resume()");
            HyprWhsprService.resume();
        }
        function cancel(): void {
            console.log("[HW IPC] → cancel()");
            HyprWhsprService.cancel();
        }
        function restart(): void {
            console.log("[HW IPC] → restart()");
            HyprWhsprService.restart();
        }
    }
}
