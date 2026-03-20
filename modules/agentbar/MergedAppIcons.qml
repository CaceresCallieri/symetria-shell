pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.config
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick

/// App icons for the merged bar's active workspace pill.
/// Reimplements WorkspaceAppIcons filtering/grouping inline (can't cross-module import).
Row {
    id: root

    required property int workspaceId

    spacing: Appearance.padding.small
    visible: cachedModel.length > 0
    height: Config.bar.sizes.indicatorHeight

    readonly property var windowLayoutEvents: new Set([
        "openwindow", "closewindow",
        "movewindow", "movewindowv2",
        "togglegroup", "moveintogroup", "moveoutofgroup"
    ])

    property var cachedModel: []

    function updateClients(): void {
        try {
            const clients = Hypr.toplevels.values.filter(c => c.workspace?.id === root.workspaceId);

            const swallowedAddresses = new Set();
            for (const c of clients) {
                const swallowing = c.lastIpcObject?.swallowing;
                if (typeof swallowing === "string" && swallowing && swallowing !== "0x0")
                    swallowedAddresses.add(swallowing);
            }

            const filtered = clients.filter(c => {
                const addr = c.lastIpcObject?.address;
                return addr && !swallowedAddresses.has(addr);
            });

            const groupMap = new Map();
            const ungrouped = [];

            for (const client of filtered) {
                const groupedArr = client.lastIpcObject?.grouped ?? [];
                if (groupedArr.length > 0) {
                    const groupKey = [...groupedArr].sort().join(',');
                    if (!groupMap.has(groupKey))
                        groupMap.set(groupKey, { canonicalOrder: groupedArr, clients: [] });
                    groupMap.get(groupKey).clients.push(client);
                } else {
                    ungrouped.push({ isGroup: false, clients: [client] });
                }
            }

            const groups = Array.from(groupMap.values()).map(group => {
                const { canonicalOrder, clients: groupClients } = group;
                groupClients.sort((a, b) => {
                    const aIdx = canonicalOrder.indexOf(a.lastIpcObject?.address);
                    const bIdx = canonicalOrder.indexOf(b.lastIpcObject?.address);
                    if (aIdx === -1 || bIdx === -1) return 0;
                    return aIdx - bIdx;
                });
                return { isGroup: true, clients: groupClients };
            });

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
            console.error("MergedAppIcons: Failed to update clients:", e);
            root.cachedModel = [];
        }
    }

    Component.onCompleted: updateDebounce.restart()
    onWorkspaceIdChanged: updateDebounce.restart()

    Timer {
        id: updateDebounce
        interval: 50
        onTriggered: root.updateClients()
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (root.windowLayoutEvents.has(event.name))
                updateDebounce.restart();
        }
    }

    move: Transition {
        Anim {
            properties: "x,y"
        }
    }

    Repeater {
        model: ScriptModel {
            values: root.cachedModel
        }

        Loader {
            required property var modelData

            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: modelData.isGroup ? groupedContainer : singleIcon

            Component {
                id: singleIcon

                MergedAppIcon {
                    client: modelData.clients[0]
                }
            }

            Component {
                id: groupedContainer

                Rectangle {
                    readonly property var glassStyle: Colours.pillStyle(
                        Colours.palette.m3surfaceContainerHigh,
                        Colours.glass.subtle
                    )

                    implicitWidth: groupRow.implicitWidth + Appearance.padding.normal * 2
                    implicitHeight: Config.bar.sizes.indicatorHeight

                    color: glassStyle.background
                    radius: Appearance.rounding.full
                    border.width: 1
                    border.color: glassStyle.border

                    Behavior on implicitWidth {
                        Anim {}
                    }

                    Row {
                        id: groupRow
                        anchors.centerIn: parent
                        spacing: Appearance.padding.small

                        Repeater {
                            model: modelData.clients

                            MergedAppIcon {
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
