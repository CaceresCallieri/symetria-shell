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

    implicitHeight: pill.implicitHeight
    implicitWidth: pill.implicitWidth

    // Layout metrics for the wrapping content row.
    readonly property int _rowHeight: Config.bar.sizes.innerWidth
    // Wrap budget: the widest a row may grow before items flow onto the next row. Leaves room for
    // the pill's own horizontal padding plus an edge margin so the capsule never touches the
    // screen edge. root.width is the full screen width (the Loader in Wrapper anchors left+right).
    readonly property int _edgeMargin: Appearance.padding.large
    readonly property int _maxContentWidth: Math.max(1, root.width - _edgeMargin * 2 - Appearance.padding.large * 2)
    // True once content occupies more than one row. This is the hinge for the whole stability
    // strategy: a single row can never re-wrap (so it animates freely and the pill hugs it),
    // whereas a wrapped layout must snap and use a fixed width (so a workspace switch can't make
    // Flow oscillate or the pill overflow the screen). 1.5× guards against float jitter at the
    // exact one-row height.
    readonly property bool _wrapped: layout.childrenRect.height > _rowHeight * 1.5

    /// Horizontal shift that centres the wrapped row containing itemY WITHIN THE FIXED CONTENT
    /// WIDTH (the Flow's budget). Because the wrapped pill is locked to that budget, centring each
    /// row within it makes every row sit centred inside the stable pill. Returns 0 on a single row
    /// (the pill hugs that row, so there's nothing to centre, and the slot animates instead).
    /// Applied as a per-item Translate (purely visual — leaves Flow's wrapping math and
    /// childrenRect untouched, so no binding loop) and fed to the ActiveIndicator so the highlight
    /// tracks centred slots. Reads live child geometry, so it re-evaluates whenever Flow relayouts.
    function _rowCenterOffset(itemY: real): real {
        if (!_wrapped)
            return 0;
        let rowRight = 0;
        const kids = layout.children;
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i];
            // Skip the Repeater objects themselves (zero width) and the hidden remote slot.
            if (!c || !c.visible || c.width <= 0)
                continue;
            const right = c.x + c.width;
            if (c.y === itemY && right > rowRight)
                rowRight = right;
        }
        return (layout.width - rowRight) / 2;
    }

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

        // Single row: hug the content (compact), and since one row never re-wraps it can animate
        // and re-centre smoothly. Wrapped: LOCK to the full budget width so the pill is STABLE —
        // it neither re-centres nor overflows the screen edge when a workspace switch changes the
        // active slot's content width (the active slot shows app icons, so that width is volatile).
        // Height always hugs the wrapped rows (childrenRect spans every row), so the capsule grows
        // in height — not width — as entries wrap.
        implicitWidth: root._wrapped
            ? root._maxContentWidth + Appearance.padding.large * 2
            : layout.childrenRect.width + Appearance.padding.large * 2
        implicitHeight: layout.childrenRect.height

        // Wrapping content row. `width` is the wrap budget: when the content would exceed it, Flow
        // breaks the next item onto a new row. Left/top anchored (not centred) with leftMargin =
        // pill padding. When wrapped the pill equals budget + padding*2, so the Flow exactly fills
        // the pill's content area and per-row Translates centre the rows within it. On a single row
        // the pill hugs childrenRect (narrower than the budget) and the Flow's empty right-hand
        // slack simply extends past the pill edge harmlessly (no children there to clip).
        Flow {
            id: layout

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: Appearance.padding.large

            width: root._maxContentWidth
            spacing: Math.floor(Appearance.spacing.small / 2)

            // Workspace slots — direct Repeater so ActiveIndicator can access items via itemAt()
            Repeater {
                id: workspaceRepeater

                model: ScriptModel {
                    values: root.filteredWorkspaces
                }

                MergedWorkspacePill {
                    id: wsDelegate

                    required property int modelData

                    // Active slot's breathing room is baked into width (content stays centred via
                    // anchors.centerIn), replacing the RowLayout left/right margins — Flow has no
                    // per-item margins. Uniform height keeps every row the same thickness.
                    width: implicitWidth + (isActive ? activePadding * 2 : 0)
                    height: root._rowHeight

                    wsId: modelData
                    visualActiveWsId: root.visualActiveWsId
                    agents: root.agentsForWorkspace(modelData)
                    occupied: root.occupied

                    // Centre this slot within its wrapped row (0 on a single row).
                    transform: Translate {
                        x: root._rowCenterOffset(wsDelegate.y)
                    }

                    // Width animates ONLY on a single row (the original smooth slide). A single row
                    // can't re-wrap, so animating is safe. When WRAPPED the width must SNAP: Flow
                    // re-wraps on child width, so animating it makes a workspace switch sweep through
                    // intermediate widths — slots flip rows mid-animation and the centering flings
                    // them to opposite ends, then glide back (the "jumping around" regression).
                    // Snapping settles the wrapped layout in one step; the ActiveIndicator still
                    // glides via its own Behaviors. DO NOT make this Behavior unconditional.
                    Behavior on width {
                        enabled: !root._wrapped
                        Anim {}
                    }
                }
            }

            // Remote agents (tunneled via SSH) — dedicated slot with cloud icon
            Item {
                id: remoteSlot

                visible: root.hasRemote
                implicitWidth: remoteSlotLayout.implicitWidth
                height: root._rowHeight

                // Centre within its wrapped row (0 on full rows). Snaps — see the regression
                // guard on the workspace delegate above.
                transform: Translate {
                    x: root._rowCenterOffset(remoteSlot.y)
                }

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

            // Orphan agents (no workspace mapping) — inline chips, wrapped in a row-height box so
            // they sit vertically centred within their Flow row (Flow top-aligns raw children).
            // ScriptModel keyed on the stable agent id (see AgentChipGroup) so a churning orphan
            // agent doesn't force a full delegate reset that flashes busy sparkles onto siblings.
            Repeater {
                model: ScriptModel {
                    values: root.hasOrphans ? root.orphanAgents : []
                    objectProp: "id"
                }

                Item {
                    id: orphanWrap

                    // intentional var: heterogeneous agent JS object from bridge JSON
                    required property var modelData

                    implicitWidth: orphanChip.implicitWidth
                    height: root._rowHeight

                    // Centre within its wrapped row (0 on full rows). Snaps — see the regression
                    // guard on the workspace delegate above.
                    transform: Translate {
                        x: root._rowCenterOffset(orphanWrap.y)
                    }

                    AgentChipFor {
                        id: orphanChip

                        anchors.verticalCenter: parent.verticalCenter
                        agent: orphanWrap.modelData
                    }
                }
            }
        }

        // Active workspace indicator (sliding highlight pill behind the layout). Its
        // verticalCenterOffset follows the active slot onto its wrapped row — rowYOffset is 0
        // while everything fits one row, so this is inert until the content actually wraps.
        Loader {
            id: indicatorLoader

            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: indicatorLoader.item?.rowYOffset ?? 0
            active: Config.bar.workspaces.activeIndicator
            asynchronous: true
            z: -1

            sourceComponent: ActiveIndicator {
                activeWsId: root.visualActiveWsId
                workspaces: workspaceRepeater
                mask: layout
                multiRow: true
                // Match the per-item Translate so the highlight tracks a centred wrapped row.
                rowXOffset: currentWs ? root._rowCenterOffset(currentWs.y) : 0
            }
        }
    }
}
