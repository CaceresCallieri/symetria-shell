import qs.components
import qs.services
import qs.utils
import qs.config
import Quickshell
import Quickshell.Hyprland
import QtQuick

// Container for workspace app icons
// Handles filtering swallowed windows, grouping, and position-based sorting
// Uses Quickshell's reactive Hyprland data with event-based updates
Row {
    id: root

    required property int workspaceId

    spacing: Appearance.padding.small
    visible: cachedModel.length > 0

    // Events that affect window positions or lifecycle (Set for O(1) lookup)
    // Explicitly excludes: fullscreen, activewindow, activewindowv2 (don't affect layout)
    readonly property var windowLayoutEvents: new Set([
        "openwindow", "closewindow",
        "movewindow", "movewindowv2",
        "togglegroup", "moveintogroup", "moveoutofgroup"
    ])

    // Cached structured model: array of {isGroup: bool, clients: []}
    property var cachedModel: []

    // Process clients and build structured model with grouped/ungrouped separation
    function updateClients() {
        try {
            const clients = Hypr.toplevels.values.filter(c => c.workspace?.id === root.workspaceId);

            // Build set of swallowed window addresses to filter out
            const swallowedAddresses = new Set();
            for (const c of clients) {
                const swallowing = c.lastIpcObject?.swallowing;
                if (typeof swallowing === "string" && swallowing && swallowing !== "0x0") {
                    swallowedAddresses.add(swallowing);
                }
            }

            // Filter out swallowed windows (with explicit null check)
            const filtered = clients.filter(c => {
                const addr = c.lastIpcObject?.address;
                return addr && !swallowedAddresses.has(addr);
            });

            // Separate grouped and ungrouped clients (like AGS)
            // Use Map for O(n) group detection - key is sorted addresses joined
            const groupMap = new Map();
            const ungrouped = [];

            for (const client of filtered) {
                const groupedArr = client.lastIpcObject?.grouped ?? [];
                if (groupedArr.length > 0) {
                    // Create stable group key from sorted addresses (handles any group member order)
                    const groupKey = [...groupedArr].sort().join(',');
                    if (!groupMap.has(groupKey)) {
                        groupMap.set(groupKey, { canonicalOrder: groupedArr, clients: [] });
                    }
                    groupMap.get(groupKey).clients.push(client);
                } else {
                    ungrouped.push({ isGroup: false, clients: [client] });
                }
            }

            // Convert groups map to array, sorting each group's clients by canonical tab order
            const groups = Array.from(groupMap.values()).map(group => {
                const { canonicalOrder, clients: groupClients } = group;
                // Sort by index in canonical order (the grouped array from first window)
                groupClients.sort((a, b) => {
                    const aIdx = canonicalOrder.indexOf(a.lastIpcObject?.address);
                    const bIdx = canonicalOrder.indexOf(b.lastIpcObject?.address);
                    if (aIdx === -1 || bIdx === -1) return 0;
                    return aIdx - bIdx;
                });
                return { isGroup: true, clients: groupClients };
            });

            // Combine and sort by first client's position (X, then Y)
            const combined = [...groups, ...ungrouped];
            combined.sort((a, b) => {
                const aClient = a.clients[0];
                const bClient = b.clients[0];
                const ax = aClient?.lastIpcObject?.at?.[0] ?? 0;
                const bx = bClient?.lastIpcObject?.at?.[0] ?? 0;
                if (ax !== bx) return ax - bx;
                const ay = aClient?.lastIpcObject?.at?.[1] ?? 0;
                const by = bClient?.lastIpcObject?.at?.[1] ?? 0;
                return ay - by;
            });

            root.cachedModel = combined;
        } catch (e) {
            console.error("WorkspaceAppIcons: Failed to update clients:", e);
            root.cachedModel = [];
        }
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

    // Move animation only - entry animation handled by individual icons via animateEntry
    // (Grouped containers are recreated on model change, so Row add transition would
    // cause all grouped items to animate on every update)
    move: Transition {
        Anim {
            properties: "x,y"
        }
    }

    Repeater {
        model: ScriptModel {
            values: root.cachedModel
        }

        // Delegate: conditionally render grouped container or single icon
        Loader {
            required property var modelData

            sourceComponent: modelData.isGroup ? groupedContainer : singleIcon

            Component {
                id: singleIcon

                WorkspaceAppIcon {
                    client: modelData.clients[0]
                }
            }

            Component {
                id: groupedContainer

                // Pill-shaped container for grouped windows (matching AGS style)
                Rectangle {
                    id: container

                    implicitWidth: groupRow.implicitWidth + Appearance.padding.normal * 2
                    implicitHeight: groupRow.implicitHeight

                    color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
                    radius: Appearance.rounding.full
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3outline, 0.3)

                    // Smooth width animation when icons are added/removed
                    Behavior on implicitWidth {
                        Anim {}
                    }

                    Row {
                        id: groupRow
                        anchors.centerIn: parent
                        spacing: 0

                        // No add/move transitions - container is recreated on model change
                        // so all icons would animate on every update

                        Repeater {
                            model: modelData.clients

                            WorkspaceAppIcon {
                                required property var modelData
                                client: modelData
                                animateEntry: false
                            }
                        }
                    }
                }
            }
        }
    }
}
