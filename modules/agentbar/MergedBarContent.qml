pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

/// Merged workspace + agent bar content. Replaces AgentBarContent when merge mode is active.
/// Single glass pill container (like the top bar workspace pill) with an ActiveIndicator
/// highlighting the current workspace. Each workspace slot shows label + agent chips + app icons.
/// Special workspaces appear at the end of the pill and the ActiveIndicator slides to them
/// when toggled on (they overlay the regular workspace, so visualActiveWsId tracks both).
Item {
    id: root

    required property ShellScreen screen

    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)

    implicitHeight: Config.bar.sizes.innerWidth
    implicitWidth: pill.implicitWidth

    // Per-monitor or global active workspace ID (same logic as Workspaces.qml)
    readonly property int activeWsId: Config.bar.workspaces.perMonitorWorkspaces
        ? (monitor?.activeWorkspace?.id ?? 1)
        : Hypr.activeWsId

    // Special workspace overlay state — a special workspace can be active simultaneously
    // with a regular workspace (it overlays). We track the active special workspace ID
    // so the ActiveIndicator can slide to it when toggled on.
    readonly property string activeSpecialName: (Config.bar.workspaces.perMonitorWorkspaces ? monitor : Hypr.focusedMonitor)?.lastIpcObject.specialWorkspace.name ?? ""
    readonly property bool onSpecial: activeSpecialName !== ""
    readonly property int activeSpecialWsId: {
        if (!onSpecial) return -1;
        const ws = Hypr.workspaceByName(activeSpecialName);
        return ws?.id ?? -1;
    }

    // Unified active ID: prefers the special workspace when one is toggled on and its
    // workspace object already exists in Hyprland's list (guards against the IPC race
    // where activeSpecialName is set before the workspace appears in workspaces.values).
    readonly property int visualActiveWsId: onSpecial && activeSpecialWsId !== -1 ? activeSpecialWsId : activeWsId

    // Occupied workspace map.
    // Computation centralized in Hypr.occupiedMap() — shared with the top bar.
    readonly property var occupied: Hypr.occupiedMap()

    // Dynamic workspace list including special workspaces at the end.
    // Sort order is centralized in Hypr.displayedWorkspaceIds():
    // named (negative, non-special) → regular (positive) → special.
    readonly property var displayedWorkspaces: Hypr.displayedWorkspaceIds(true, root.activeWsId)

    // Grouped agents by workspace. Args are unused in the body — they exist solely
    // to make QML track AgentService.agents and _workspaceMap as binding dependencies
    // (same pattern as AgentService._sortProjectsByWorkspace).
    readonly property var _agentGrouping: _computeAgentGrouping(AgentService.agents, AgentService._workspaceMap)

    function _computeAgentGrouping(_agentsDep: var, _wsMapDep: var): var {
        return AgentService.agentsByWorkspace();
    }

    function agentsForWorkspace(wsId: int): var {
        return _agentGrouping.byWorkspace[wsId] ?? [];
    }

    // Per-monitor workspace filtering (includes special workspaces bound to this monitor).
    // activeWsId and activeSpecialWsId are added as sentinels so the active slot is never
    // filtered out even if Hyprland hasn't yet reflected monitor assignment.
    readonly property var filteredWorkspaces: {
        if (!Config.bar.workspaces.perMonitorWorkspaces)
            return displayedWorkspaces;

        const mon = root.monitor;
        if (!mon) return displayedWorkspaces;

        const monWsIds = new Set();
        for (const ws of Hypr.workspaces.values) {
            if (ws.monitor === mon)
                monWsIds.add(ws.id);
        }
        monWsIds.add(root.activeWsId);
        if (root.onSpecial && root.activeSpecialWsId !== -1)
            monWsIds.add(root.activeSpecialWsId);

        return displayedWorkspaces.filter(id => monWsIds.has(id));
    }

    // Orphan agents (no workspace mapping)
    readonly property var orphanAgents: _agentGrouping.orphans
    readonly property bool hasOrphans: orphanAgents.length > 0

    // Remote agents (tunneled via SSH, no local Hyprland window)
    readonly property var remoteAgents: _agentGrouping.remote
    readonly property bool hasRemote: remoteAgents.length > 0

    // Group remote agents by project — Array<agentArray>, one inner array per project.
    // Shape matches MergedWorkspacePill._clusterGroups so the same AgentChipGroup Repeater
    // pattern can be used: agents: modelData, workspaceName: "" (always show label for remote).
    readonly property var _remoteProjectGroups: {
        const groups = {};
        const order = [];
        for (const agent of root.remoteAgents) {
            const p = agent.project ?? "unknown";
            if (!groups[p]) {
                groups[p] = [];
                order.push(p);
            }
            groups[p].push(agent);
        }
        return order.map(p => groups[p]);
    }

    // Outer pill — shared claymorphism surface, matches the top-bar workspace pill.
    // Full-bleed overlays (ActiveIndicator) clip against its rounded shape.
    PillSurface {
        id: pill

        anchors.centerIn: parent

        implicitHeight: Config.bar.sizes.innerWidth
        implicitWidth: layout.implicitWidth + Appearance.padding.large * 2

        RowLayout {
            id: layout

            anchors.centerIn: parent
            spacing: Math.floor(Appearance.spacing.small / 2)

            // Workspace slots — direct Repeater so ActiveIndicator can access items via itemAt()
            Repeater {
                id: workspaceRepeater

                model: ScriptModel {
                    values: root.filteredWorkspaces
                }

                MergedWorkspacePill {
                    required property int modelData

                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: implicitWidth
                    Layout.leftMargin: isActive ? activePadding : 0
                    Layout.rightMargin: isActive ? activePadding : 0

                    wsId: modelData
                    visualActiveWsId: root.visualActiveWsId
                    agents: root.agentsForWorkspace(modelData)
                    occupied: root.occupied

                    Behavior on Layout.preferredWidth { Anim {} }
                    Behavior on Layout.leftMargin { Anim {} }
                    Behavior on Layout.rightMargin { Anim {} }
                }
            }

            // Remote agents (tunneled via SSH) — dedicated slot with cloud icon
            Item {
                id: remoteSlot

                visible: root.hasRemote
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: remoteSlotLayout.implicitWidth

                RowLayout {
                    id: remoteSlotLayout

                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Appearance.spacing.smaller

                    // Cloud icon identifying this as a remote slot
                    MaterialIcon {
                        text: "cloud_queue"
                        color: Colours.palette.m3onSurfaceVariant
                        font.pointSize: Appearance.font.size.small
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // Per-project groups: reuse AgentChipGroup (project label + chips).
                    // workspaceName: "" → always show the label (remote has no local workspace).
                    Repeater {
                        model: root._remoteProjectGroups

                        AgentChipGroup {
                            // intentional var: JS array of one project's agents from _remoteProjectGroups
                            required property var modelData

                            Layout.alignment: Qt.AlignVCenter
                            agents: modelData
                            workspaceName: ""
                        }
                    }
                }
            }

            // Orphan agents (no workspace mapping) — inline chips. ScriptModel keyed on the
            // stable agent id (see AgentChipGroup) so a churning orphan agent doesn't force a
            // full delegate reset that flashes busy sparkles onto its idle siblings.
            Repeater {
                model: ScriptModel {
                    values: root.hasOrphans ? root.orphanAgents : []
                    objectProp: "id"
                }

                AgentChipFor {
                    required property var modelData

                    Layout.alignment: Qt.AlignVCenter
                    agent: modelData
                }
            }
        }

        // Active workspace indicator (sliding highlight pill behind the layout)
        Loader {
            anchors.verticalCenter: parent.verticalCenter
            active: Config.bar.workspaces.activeIndicator
            asynchronous: true
            z: -1

            sourceComponent: ActiveIndicator {
                activeWsId: root.visualActiveWsId
                workspaces: workspaceRepeater
                mask: layout
            }
        }
    }
}
