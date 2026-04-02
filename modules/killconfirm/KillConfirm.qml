pragma ComponentBehavior: Bound

import qs.services
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

/// IPC handler for the kill-window confirmation overlay.
///
/// When triggered, captures the focused window's title/class BEFORE the overlay
/// maps (which steals focus via WlrKeyboardFocus.Exclusive, nullifying activeToplevel).
/// On confirm, dispatches `forcekillactive` back to Hyprland.
Scope {
    id: root

    /// Whether the confirmation overlay is active.
    property bool active: false

    /// Captured window info — frozen at prompt time so the overlay can display it
    /// even after exclusive keyboard focus shifts away from the original window.
    property string windowTitle: ""
    property string windowClass: ""

    /// The monitor that was focused when the prompt was triggered.
    property var targetMonitor: null

    function prompt(): void {
        if (active) {
            dismiss();
            return;
        }

        const toplevel = Hypr.activeToplevel;
        if (!toplevel) {
            console.warn("[KillConfirm] No active toplevel to kill");
            return;
        }

        windowTitle = toplevel.title ?? "";
        windowClass = toplevel.lastIpcObject?.class ?? "";
        targetMonitor = Hypr.focusedMonitor;
        active = true;
    }

    function confirm(): void {
        dismiss();
        Hypr.dispatch("forcekillactive");
    }

    function dismiss(): void {
        active = false;
        windowTitle = "";
        windowClass = "";
        targetMonitor = null;
    }

    IpcHandler {
        target: "killconfirm"

        function prompt(): void {
            root.prompt();
        }
    }
}
