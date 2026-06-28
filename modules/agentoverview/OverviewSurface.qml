pragma ComponentBehavior: Bound

import qs.components
import qs.components.containers
import qs.components.misc
import qs.services
import qs.config
import qs.utils
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

/// Layer-shell surface for the Agent Overview feature.
///
/// One window per screen via Variants; only the variant whose monitor matches
/// AgentOverviewService.targetMonitor maps. A dimmed scrim, an All/Active/Dormant
/// filter, and a LIVE workspace-grouped grid of agent cards. Esc dismisses; Tab
/// (or 1/2/3) cycles the filter; clicking a card focuses that agent and closes.
///
/// Unlike WindowOverview this does NOT freeze a snapshot — content binds
/// reactively to AgentService via AgentOverviewService.filteredGrouping, so cards
/// appear/disappear and update in place as agents work.
///
/// Layout note: the card grid uses plain Column/Flow with explicit widths
/// (availWidth threaded down), NOT a Flow inside a Layout — a Flow's
/// implicitHeight depends on its width, which a Layout derives from
/// implicitHeight, producing a binding loop. Plain positioners avoid it.
Scope {
    id: root

    // Inline components live at the file root (matching every other inline
    // component in the codebase) and reference only singletons + the sibling
    // AgentOverviewCard — never the per-window ids — so they are scope-safe.

    // ── Reusable All/Active/Dormant filter segment ───────────────────
    component FilterButton: StyledRect {
        id: fbtn

        required property string mode
        required property string label
        required property int count
        readonly property bool current: AgentOverviewService.filterMode === fbtn.mode

        radius: Appearance.rounding.full
        implicitHeight: fbtnRow.implicitHeight + Appearance.padding.small * 2
        implicitWidth: fbtnRow.implicitWidth + Appearance.padding.large * 2
        color: fbtn.current ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh
        border.width: 1
        border.color: fbtn.current ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

        RowLayout {
            id: fbtnRow
            anchors.centerIn: parent
            spacing: Appearance.spacing.small

            StyledText {
                text: fbtn.label
                color: fbtn.current ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                font.pointSize: Appearance.font.size.small
                font.weight: fbtn.current ? Font.Bold : Font.Normal
            }
            StyledText {
                text: fbtn.count
                color: fbtn.current ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.small
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: AgentOverviewService.setFilter(fbtn.mode)
        }
    }

    // ── One workspace/remote/orphan group: header + wrapping card grid ──
    component GroupSection: Column {
        id: section

        required property var group
        required property real availWidth
        readonly property string kind: section.group.kind
        readonly property var agents: section.group.agents
        readonly property string wsIcon: section.kind === "ws" ? AgentService.workspaceIconForWsId(section.group.wsId) : ""
        readonly property var parsedWs: section.wsIcon !== "" ? Icons.parseIcon(section.wsIcon) : null
        readonly property bool wsMaterial: section.parsedWs !== null && section.parsedWs.useMaterial === true
        readonly property string headerLabel: {
            if (section.kind === "remote")
                return "Remote";
            if (section.kind === "orphans")
                return "No workspace";
            const ws = Hypr.workspaceById(section.group.wsId);
            return ws && ws.name ? ws.name : ("Workspace " + section.group.wsId);
        }

        width: section.availWidth
        spacing: Appearance.spacing.small

        // Group header (sized to content)
        RowLayout {
            spacing: Appearance.spacing.small

            MaterialIcon {
                visible: section.kind !== "ws" || section.wsMaterial
                text: {
                    if (section.kind === "remote")
                        return "cloud_queue";
                    if (section.kind === "orphans")
                        return "device_unknown";
                    return section.parsedWs ? section.parsedWs.iconText : "";
                }
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.normal
            }
            StyledText {
                visible: section.kind === "ws" && !section.wsMaterial
                text: section.parsedWs ? section.parsedWs.iconText : ""
                color: Colours.palette.m3onSurfaceVariant
                font.weight: Font.DemiBold
                font.pointSize: Appearance.font.size.normal
            }
            StyledText {
                text: section.headerLabel
                color: Colours.palette.m3onSurface
                font.weight: Font.Bold
                font.pointSize: Appearance.font.size.normal
            }
            StyledText {
                text: "· " + section.agents.length
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.small
            }
        }

        // Wrapping card grid — explicit width, no Layout (see file note)
        Flow {
            width: section.width
            spacing: Appearance.spacing.smaller

            Repeater {
                // ScriptModel keyed on stable agent id so a churning agent
                // updates in place instead of resetting sibling cards (and
                // restarting their sparkles) — see ProjectGroup/MEMORY.md.
                model: ScriptModel {
                    values: section.agents
                    objectProp: "id"
                }

                AgentOverviewCard {
                    required property var modelData
                    agent: modelData
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData

            readonly property bool shouldShow: AgentOverviewService.active && AgentOverviewService.targetMonitor === Hypr.monitorFor(modelData)

            /// Ordered group descriptors for the grid: numbered workspaces first
            /// (ascending), then Remote, then orphans. Keyed by a stable `key` so
            /// the outer Repeater's ScriptModel updates groups in place.
            // Only the visible surface builds cards — keeps a multi-monitor setup
            // from instantiating N copies of the grid (and N sets of live sparkles).
            readonly property var groups: win.shouldShow ? win._buildGroups(AgentOverviewService.filteredGrouping) : []

            function _buildGroups(g: var): var {
                const out = [];
                const wsIds = Object.keys(g.byWorkspace).map(k => parseInt(k)).sort((a, b) => a - b);
                for (const id of wsIds)
                    out.push({ key: "ws" + id, kind: "ws", wsId: id, agents: g.byWorkspace[id] });
                if (g.remote.length > 0)
                    out.push({ key: "remote", kind: "remote", wsId: 0, agents: g.remote });
                if (g.orphans.length > 0)
                    out.push({ key: "orphans", kind: "orphans", wsId: 0, agents: g.orphans });
                return out;
            }

            screen: modelData
            name: "agentoverview-surface"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            visible: shouldShow

            mask: inputRegion

            Region {
                id: inputRegion
                x: 0
                y: 0
                width: win.shouldShow ? win.width : 0
                height: win.shouldShow ? win.height : 0
            }

            FocusManager {
                active: win.shouldShow
                target: surface
            }

            FocusScope {
                id: surface

                anchors.fill: parent
                focus: true

                Keys.onEscapePressed: event => {
                    event.accepted = true;
                    AgentOverviewService.hide();
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Tab) {
                        event.accepted = true;
                        AgentOverviewService.cycleFilter();
                    } else if (event.key === Qt.Key_Backtab) {
                        event.accepted = true;
                        AgentOverviewService.cycleFilterReverse();
                    } else if (event.key === Qt.Key_1) {
                        event.accepted = true;
                        AgentOverviewService.setFilter("all");
                    } else if (event.key === Qt.Key_2) {
                        event.accepted = true;
                        AgentOverviewService.setFilter("active");
                    } else if (event.key === Qt.Key_3) {
                        event.accepted = true;
                        AgentOverviewService.setFilter("dormant");
                    }
                }

                // Dimmed scrim — click anywhere outside the cards to dismiss.
                Rectangle {
                    anchors.fill: parent
                    color: Colours.palette.m3scrim
                    opacity: 0.65

                    MouseArea {
                        anchors.fill: parent
                        onClicked: AgentOverviewService.hide()
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Appearance.padding.large * 2
                    spacing: Appearance.spacing.large

                    // Header: title + filter
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.spacing.normal

                        StyledText {
                            text: "Agents"
                            color: Colours.palette.m3onSurface
                            font.weight: Font.Bold
                            font.pointSize: Appearance.font.size.extraLarge
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        FilterButton {
                            mode: "all"
                            label: "All"
                            count: AgentOverviewService.aliveCount
                        }
                        FilterButton {
                            mode: "active"
                            label: "Active"
                            count: AgentOverviewService.activeCount
                        }
                        FilterButton {
                            mode: "dormant"
                            label: "Dormant"
                            count: AgentOverviewService.dormantCount
                        }
                    }

                    // Empty state (Layouts skip invisible items, so this and the
                    // flickable never both consume vertical space)
                    StyledText {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: win.groups.length === 0
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        // Invariant: with filterMode "all" and an empty grid, aliveCount
                        // is necessarily 0 → the first arm wins, so the dynamic
                        // "No <mode> agents" message only ever reads active/dormant.
                        text: AgentOverviewService.aliveCount === 0 ? "No agents running" : ("No " + AgentOverviewService.filterMode + " agents")
                        color: Colours.palette.m3onSurfaceVariant
                        font.pointSize: Appearance.font.size.large
                    }

                    // Grouped grid
                    StyledFlickable {
                        id: flick

                        visible: win.groups.length > 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: groupsCol.height

                        Column {
                            id: groupsCol
                            width: flick.width
                            spacing: Appearance.spacing.large

                            Repeater {
                                model: ScriptModel {
                                    values: win.groups
                                    objectProp: "key"
                                }

                                GroupSection {
                                    required property var modelData
                                    group: modelData
                                    availWidth: groupsCol.width
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
