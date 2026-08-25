pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell
import Quickshell.Hyprland
import QtQuick

/// Workspace app icons with each agent's sparkle chip interleaved immediately to the
/// right of the icon for the window hosting it (matched by terminal_pid → window pid).
///
/// The agentbar owns this interleaving: it can't live in the shared
/// components/WorkspaceAppIcons because AgentChip is an agentbar type, and a
/// components → modules import would be a cycle. Window grouping/sorting/refresh is
/// reused from the shared headless WorkspaceWindowModel, so only the icon+chip render
/// differs from the top-bar path.
Row {
    id: root

    required property int workspaceId
    // intentional var: heterogeneous agent JS objects from AgentService bridge JSON
    required property var agents
    /// Workspace name, forwarded to each HostedAgentIcon for the project-label visibility rule.
    required property string workspaceName

    /// See WorkspaceAppIcons.animateGroupWidth: false when an outer container already
    /// animates total width (the merged pill does), to avoid double-easing.
    property bool animateGroupWidth: true

    // Shared headless provider — same window model the top bar uses.
    // Declared first: _agentsByPid and unmatchedAgents both bind to windowModel.model.
    readonly property WorkspaceWindowModel windowModel: WorkspaceWindowModel {
        workspaceId: root.workspaceId
    }

    // pid → agent[], for placing each agent's chip next to its host window.
    // intentional var: JS object used as hash map (pid → agent[])
    readonly property var _agentsByPid: {
        const map = {};
        for (const a of root.agents) {
            const pid = a.terminal_pid;
            if (pid > 0) {
                if (!map[pid])
                    map[pid] = [];
                map[pid].push(a);
            }
        }
        return map;
    }

    /// Agents whose host window is not in the current model (terminal swallowed, window
    /// closed, or not on this workspace). Surfaced by the parent as a trailing cluster so
    /// an agent never silently disappears just because its window icon isn't shown.
    ///
    /// Assumes lastIpcObject.pid is stable for a window's lifetime as seen by this model —
    /// i.e., pid does not silently change without triggering a window layout event that causes
    /// WorkspaceWindowModel to rebuild. This holds because Hyprland does not reassign pids
    /// mid-session, and the workspace model is rebuilt on all open/close/move events.
    // intentional var: JS array of agent objects
    readonly property var unmatchedAgents: {
        const shownPids = new Set();
        for (const entry of root.windowModel.model)
            for (const c of entry.clients) {
                const pid = c.lastIpcObject?.pid;
                if (pid !== undefined && pid !== null)
                    shownPids.add(pid);
            }
        return root.agents.filter(a => !(a.terminal_pid > 0 && shownPids.has(a.terminal_pid)));
    }

    spacing: Appearance.padding.small
    visible: root.windowModel.model.length > 0
    height: Config.bar.sizes.indicatorHeight

    // Move animation only — entry animation handled by individual icons via animateEntry.
    move: Transition {
        Anim {
            properties: "x,y"
        }
    }

    Repeater {
        model: ScriptModel {
            values: root.windowModel.model
        }

        // Delegate: render a grouped (tab-group) pill or a single window, each with its
        // hosted chips. `required property var modelData` (not `required modelData`) is
        // mandatory here — see WorkspaceAppIcons / docs/qml-pitfalls.md.
        Loader {
            required property var modelData

            // parent?. (not parent.) — a Repeater delegate root evaluates its bindings
            // once before it is reparented, so the bare form throws on every creation.
            // See docs/qml-pitfalls.md (Repeater delegate's parent is null).
            anchors.verticalCenter: parent?.verticalCenter
            sourceComponent: modelData.isGroup ? groupedContainer : singleEntry

            Component {
                id: singleEntry

                HostedAgentIcon {
                    client: modelData.clients[0]
                    hostedAgents: root._agentsByPid[modelData.clients[0]?.lastIpcObject?.pid] ?? []
                    workspaceName: root.workspaceName
                }
            }

            Component {
                id: groupedContainer

                // Pill-shaped container for grouped (tab-group) windows.
                // NOTE: mirrors the grouped-container chrome in components/WorkspaceAppIcons.qml.
                // Kept as a small visual duplicate (styling only, no logic) rather than extracting
                // a shared pill, to avoid widening the change into the working top-bar render path
                // beyond the agreed window-model share. If this styling changes, update both.
                Rectangle {
                    id: container

                    // intentional var: heterogeneous JS { background, border }
                    readonly property var glassStyle: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)

                    implicitWidth: groupRow.implicitWidth + Appearance.padding.normal * 2
                    implicitHeight: Config.bar.sizes.indicatorHeight

                    color: glassStyle.background
                    radius: Appearance.rounding.full
                    border.width: 1
                    border.color: glassStyle.border

                    Behavior on implicitWidth {
                        enabled: root.animateGroupWidth
                        Anim {}
                    }

                    Row {
                        id: groupRow
                        anchors.centerIn: parent
                        spacing: Appearance.padding.small

                        Repeater {
                            model: modelData.clients

                            HostedAgentIcon {
                                required property HyprlandToplevel modelData

                                client: modelData
                                hostedAgents: root._agentsByPid[modelData?.lastIpcObject?.pid] ?? []
                                workspaceName: root.workspaceName
                                animateEntry: false
                            }
                        }
                    }
                }
            }
        }
    }
}
