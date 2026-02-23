pragma ComponentBehavior: Bound

import qs.services
import qs.config
import Quickshell
import Quickshell.Io
import QtQuick

/// Root component for KeyChords which-key style overlay.
///
/// Listens to KeyChordsService.active changes to show/hide the overlay
/// on the focused monitor. Exposes IPC for triggering chord groups.
Scope {
    Connections {
        target: KeyChordsService

        function onActiveChanged(): void {
            if (!Config.keychords.enabled)
                return;

            if (KeyChordsService.active) {
                const vis = Visibilities.getForActive();
                if (vis) vis.keychords = true;
            } else {
                for (const [_, v] of Visibilities.screens)
                    v.keychords = false;
            }
        }
    }

    IpcHandler {
        target: "chords"

        function activate(group: string): void {
            KeyChordsService.activate(group);
        }

        function dismiss(): void {
            KeyChordsService.dismiss();
        }
    }
}
