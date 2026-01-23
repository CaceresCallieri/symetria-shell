pragma ComponentBehavior: Bound

import qs.services
import qs.config
import Quickshell
import QtQuick

/// Root component for HyprWhsprService speech-to-text drawer.
///
/// Auto-shows the drawer on all screens when HyprWhsprService becomes active.
/// Unlike Askpass, this is triggered by service state changes, not IPC.
Scope {
    Connections {
        target: HyprWhsprService

        function onActiveChanged(): void {
            if (!Config.hyprwhspr.enabled)
                return;

            if (HyprWhsprService.active) {
                // Show on all screens
                for (const [_, visibilities] of Visibilities.screens) {
                    visibilities.hyprwhspr = true;
                }
                console.log("HyprWhsprService: Drawer shown");
            } else {
                // Hide on all screens
                for (const [_, visibilities] of Visibilities.screens) {
                    visibilities.hyprwhspr = false;
                }
                console.log("HyprWhsprService: Drawer hidden");
            }
        }
    }
}
