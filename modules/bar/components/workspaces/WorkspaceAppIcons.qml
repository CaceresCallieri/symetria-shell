import qs.components
import qs.services
import qs.utils
import qs.config
import Quickshell
import Quickshell.Hyprland
import QtQuick

// Container for workspace app icons
// Handles filtering swallowed windows and position-based sorting
// Uses Quickshell's reactive Hyprland data with event-based updates
Row {
    id: root

    required property int workspaceId

    spacing: 0
    visible: cachedClients.length > 0

    // Events that affect window positions or lifecycle (Set for O(1) lookup)
    // Explicitly excludes: fullscreen, activewindow, activewindowv2 (don't affect layout)
    readonly property var windowLayoutEvents: new Set([
        "openwindow", "closewindow",
        "movewindow", "movewindowv2",
        "togglegroup", "moveintogroup", "moveoutofgroup"
    ])

    // Cached sorted client list - only updated on specific events
    property var cachedClients: []

    // Process and sort clients for this workspace
    function updateClients() {
        const clients = Hypr.toplevels.values.filter(c => c.workspace?.id === root.workspaceId);

        // Build set of swallowed window addresses to filter out
        const swallowedAddresses = new Set();
        for (const c of clients) {
            const swallowing = c.lastIpcObject?.swallowing;
            // Null safety: ensure swallowing is a valid string address
            if (typeof swallowing === "string" && swallowing && swallowing !== "0x0") {
                swallowedAddresses.add(swallowing);
            }
        }

        // Filter out swallowed windows
        const filtered = clients.filter(c => !swallowedAddresses.has(c.lastIpcObject?.address));

        // Sort by X position first, then Y (like AGS)
        // IMPORTANT: Stable sort preserves hyprctl's native order for grouped/tabbed windows
        // (which all have identical positions). This ensures tabs appear in creation order.
        filtered.sort((a, b) => {
            const ax = a.lastIpcObject?.at?.[0] ?? 0;
            const bx = b.lastIpcObject?.at?.[0] ?? 0;
            if (ax === bx) {
                return (a.lastIpcObject?.at?.[1] ?? 0) - (b.lastIpcObject?.at?.[1] ?? 0);
            }
            return ax - bx;
        });

        root.cachedClients = filtered;
    }

    // Use debounce for all initialization paths to prevent race conditions
    Component.onCompleted: updateDebounce.restart()
    onWorkspaceIdChanged: updateDebounce.restart()

    // Debounce timer - coalesces rapid events into single update
    Timer {
        id: updateDebounce
        interval: 50  // Small delay to let Quickshell process the event
        onTriggered: root.updateClients()
    }

    // Listen to Hyprland events - only update on relevant events
    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent) {
            if (root.windowLayoutEvents.has(event.name)) {
                updateDebounce.restart();
            }
        }
    }

    // Entry animation
    add: Transition {
        Anim {
            properties: "scale"
            from: 0
            to: 1
            easing.bezierCurve: Appearance.anim.curves.standardDecel
        }
    }

    // Move animation
    move: Transition {
        Anim {
            properties: "scale"
            to: 1
            easing.bezierCurve: Appearance.anim.curves.standardDecel
        }
        Anim {
            properties: "x,y"
        }
    }

    Repeater {
        model: ScriptModel {
            values: root.cachedClients
        }

        WorkspaceAppIcon {
            required property var modelData
            client: modelData
        }
    }
}
