import qs.components
import qs.services
import qs.utils
import qs.config
import Quickshell
import QtQuick

// Container for workspace app icons
// Handles filtering swallowed windows, grouping by app class, and position-based sorting
Row {
    id: root

    required property int workspaceId

    spacing: 0

    // Process clients: filter swallowed windows, sort by position
    function processClients(clients: list<var>): list<var> {
        // 1. Build set of swallowed window addresses to filter out
        const swallowedAddresses = new Set();
        for (const c of clients) {
            const swallowing = c.lastIpcObject.swallowing;
            // "0x0", empty string, or falsy means not swallowing anything
            if (swallowing && swallowing !== "0x0" && swallowing !== "") {
                swallowedAddresses.add(swallowing);
            }
        }

        // 2. Filter out swallowed windows (each window gets its own icon)
        const filtered = clients.filter(c => !swallowedAddresses.has(c.lastIpcObject.address));

        // 3. Sort by X position (left-to-right on screen)
        filtered.sort((a, b) => {
            const posA = a.lastIpcObject.at?.[0] ?? 0;
            const posB = b.lastIpcObject.at?.[0] ?? 0;
            return posA - posB;
        });

        return filtered;
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
            values: root.processClients(
                Hypr.toplevels.values.filter(c => c.workspace?.id === root.workspaceId)
            )
        }

        WorkspaceAppIcon {
            required property var modelData
            client: modelData
        }
    }
}
