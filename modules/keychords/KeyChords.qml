pragma ComponentBehavior: Bound

import qs.services
import Quickshell
import Quickshell.Io

/// IPC handler for KeyChords which-key overlay.
///
/// Visibility is managed directly by KeyChordsOverlay using KeyChordsService state,
/// decoupled from the Drawers PersistentProperties system.
Scope {
    // Note: visibility management previously lived here (setting vis.keychords on PersistentProperties).
    // Now handled directly by KeyChordsOverlay via KeyChordsService.active + targetMonitor,
    // decoupled from the Drawers visibility system to avoid HyprlandFocusGrab conflicts.

    IpcHandler {
        target: "chords"

        function activate(group: string): void {
            console.warn("[KeyChords:IPC] activate IPC received, group:", group);
            KeyChordsService.activate(group);
        }

        function dismiss(): void {
            console.warn("[KeyChords:IPC] dismiss IPC received");
            KeyChordsService.dismiss();
        }
    }
}
