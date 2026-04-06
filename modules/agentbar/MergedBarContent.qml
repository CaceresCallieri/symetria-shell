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
        const ws = Hypr.workspaces.values.find(w => w.name === activeSpecialName);
        return ws?.id ?? -1;
    }

    // Unified active ID: prefers the special workspace when one is toggled on and its
    // workspace object already exists in Hyprland's list (guards against the IPC race
    // where activeSpecialName is set before the workspace appears in workspaces.values).
    readonly property int visualActiveWsId: onSpecial && activeSpecialWsId !== -1 ? activeSpecialWsId : activeWsId

    // Occupied workspace map
    readonly property var occupied: Hypr.workspaces.values.reduce((acc, curr) => {
        acc[curr.id] = curr.lastIpcObject.windows > 0;
        return acc;
    }, {})

    // Dynamic workspace list: occupied + active + named + special workspaces.
    // Sort order: named (negative, non-special) → regular (positive) → special (at end).
    readonly property var displayedWorkspaces: {
        const allWorkspaces = Hypr.workspaces.values
        const regularAndNamed = allWorkspaces.filter(w => !w.name.startsWith("special:"))
        const specialWs = allWorkspaces.filter(w => w.name.startsWith("special:"))

        const occupiedWs = regularAndNamed.filter(w => w.lastIpcObject.windows > 0)
        const activeId = root.activeWsId

        const namedWsNames = Config.bar.workspaces.namedWorkspaceIcons.map(n => n.name)
        const namedWs = regularAndNamed.filter(w => namedWsNames.includes(w.name))

        let ids = [...new Set([...occupiedWs.map(w => w.id), ...namedWs.map(w => w.id)])]

        if (!ids.includes(activeId))
            ids.push(activeId)

        // Append special workspace IDs (de-dup at end in case any special ws was already included)
        for (const sw of specialWs)
            ids.push(sw.id);
        ids = [...new Set(ids)];

        // Build a name lookup for sort categorization
        const nameById = {};
        for (const w of allWorkspaces)
            nameById[w.id] = w.name;

        // Sort: named (category 0) → regular (category 1) → special (category 2)
        return ids.sort((a, b) => {
            const catA = _wsSortCategory(a, nameById[a] ?? "");
            const catB = _wsSortCategory(b, nameById[b] ?? "");
            if (catA !== catB) return catA - catB;
            return a - b;
        });
    }

    function _wsSortCategory(wsId: int, wsName: string): int {
        if (wsName.startsWith("special:")) return 2;
        if (wsId < 0) return 0;
        return 1;
    }

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

    // Group remote agents by project for display: [{project: "foo", agents: [...]}]
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
        return order.map(p => ({ project: p, agents: groups[p] }));
    }

    // Glass style for the outer container (matches top bar workspace pill)
    readonly property var glassStyle: Colours.pillStyle(
        Colours.palette.m3surfaceContainerHigh,
        Colours.glass.subtle
    )

    StyledClippingRect {
        id: pill

        anchors.centerIn: parent

        implicitHeight: Config.bar.sizes.innerWidth
        implicitWidth: layout.implicitWidth + Appearance.padding.large * 2

        color: root.glassStyle.background
        radius: Appearance.rounding.full
        border.width: 1
        border.color: root.glassStyle.border

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

                    // Per-project groups: project name + agent chips
                    Repeater {
                        model: root._remoteProjectGroups

                        RowLayout {
                            required property var modelData
                            // Alias to avoid shadowing by inner Repeater's modelData
                            readonly property var groupData: modelData

                            Layout.alignment: Qt.AlignVCenter
                            spacing: Appearance.spacing.smaller

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                text: groupData.project
                                color: Colours.palette.m3primary
                                font.weight: Font.Bold
                                font.pointSize: Appearance.font.size.small
                            }

                            Repeater {
                                model: groupData.agents

                                AgentChip {
                                    required property var modelData

                                    Layout.alignment: Qt.AlignVCenter

                                    active: modelData.active ?? false
                                    activityState: modelData.activity_state ?? ""
                                    activityTool: modelData.activity_tool ?? ""
                                    isSttTarget: AgentService.isAgentSttTarget(modelData)
                                }
                            }
                        }
                    }
                }
            }

            // Orphan agents (no workspace mapping) — inline chips
            Repeater {
                model: root.hasOrphans ? root.orphanAgents : []

                AgentChip {
                    required property var modelData

                    Layout.alignment: Qt.AlignVCenter

                    active: modelData.active ?? false
                    activityState: modelData.activity_state ?? ""
                    activityTool: modelData.activity_tool ?? ""
                    isSttTarget: AgentService.isAgentSttTarget(modelData)
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
