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
import QtQuick.Layouts

/// Per-workspace slot in the merged bar: workspace label, then window icons each followed by
/// their hosted agent's project label + chip ([icon] (name) ⭐), plus a trailing cluster for
/// agents with no shown window (and all agents on inactive workspaces).
/// Handles both regular and special workspaces — special workspaces use different icon resolution
/// (getSpecialWsIcon) and click behavior (togglespecialworkspace instead of workspace switch).
/// No background — the outer MergedBarContent container provides the glass pill,
/// and ActiveIndicator (shared component) provides the active workspace highlight.
Item {
    id: root

    required property int wsId
    required property int visualActiveWsId
    // intentional var: heterogeneous JS objects from AgentService bridge JSON
    required property var agents
    // intentional var: JS object used as hash map ({ [wsId]: bool })
    required property var occupied

    // ActiveIndicator contract — matches Workspace.qml's interface
    readonly property bool isWorkspace: true
    readonly property int ws: wsId
    readonly property bool isActive: visualActiveWsId === ws
    readonly property int activePadding: Appearance.padding.large
    // In the merged Flow the active slot's breathing room is baked into the item's WIDTH (content
    // stays centred via anchors.centerIn), replacing the RowLayout left/right margins that Flow
    // cannot express. So x is the box's left edge and the box itself already spans the full
    // highlight extent — the indicator needs no extra horizontal offset.
    readonly property int indicatorOffset: 0
    readonly property int indicatorSize: implicitWidth + (isActive ? activePadding * 2 : 0)

    // Workspace state
    readonly property bool isOccupied: occupied[ws] ?? false

    // Whether window icons render in this slot: active + occupied workspace, respecting the
    // special-workspace window-visibility flag. Same gate the old WorkspaceAppIcons Loader used.
    // Drives whether agent chips interleave with window icons (true) or fall back to a trailing
    // cluster (false — e.g. inactive workspaces, which show no window icons).
    readonly property bool windowsVisible: root.isActive && root.isOccupied
        && (root.isSpecial ? Config.bar.workspaces.showWindowsOnSpecialWorkspaces : Config.bar.workspaces.showWindows)

    // Special workspace detection.
    // Hypr.workspaceById() centralizes the .find() pattern shared with the
    // top-bar Workspace.qml and AgentService.
    // intentional var: Hyprland workspace proxy from .find() — nullable, identity-unstable
    readonly property var currentWorkspace: Hypr.workspaceById(root.ws)
    readonly property string currentWorkspaceName: currentWorkspace?.name ?? ""  // "" when workspace not yet reported by Hyprland
    readonly property bool isSpecial: currentWorkspaceName.startsWith("special:")

    // Icon resolution: special → getSpecialWsIcon, named → getNamedWsIcon, numbered → romanize
    // Uses AgentService.workspaceIconForWsId() which already handles all three cases.
    readonly property string rawIcon: AgentService.workspaceIconForWsId(root.ws)
    // intentional var: JS object { useMaterial: bool, iconText: string } from Icons.parseIcon()
    readonly property var parsedIcon: Icons.parseIcon(rawIcon)

    // Color: active uses onSurface, inactive uses muted variant
    readonly property color labelColor: isActive ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant

    // Cluster agents grouped by project so each group's chips carry their project name via
    // AgentChipGroup — matching the interleaved layout's [icon] (name) ⭐.
    //
    // Agents in scope: active workspace → only unmatched agents (host window not shown);
    // inactive workspace → all of this workspace's agents. (Inlined from the former
    // _clusterAgents intermediate property, which had a single consumer here.)
    //
    // Project order MUST match the active interleaved row, which follows AppIconsProcessor's
    // window position sort. Grouping in bridge/first-seen order instead made an inactive
    // workspace's projects appear inverted relative to when it's active. So we sort projects
    // by their host window's index in the SAME processor output the active row consumes —
    // identical ordering by construction. Windows on inactive workspaces still report
    // positions via Hypr.toplevels, so this works even when no icons are rendered here.
    // intentional var: JS array of agent-arrays, one per project
    readonly property var _clusterGroups: {
        const clusterAgents = root.windowsVisible
            ? (hostedRow.item?.unmatchedAgents ?? [])
            : root.agents;

        const groups = {};
        const order = [];
        for (const agent of clusterAgents) {
            const p = agent.project ?? "unknown";
            if (!groups[p]) {
                groups[p] = [];
                order.push(p);
            }
            groups[p].push(agent);
        }

        // pid → position index from the canonical window sort for this workspace.
        // HACK: calls processClients() directly instead of going through WorkspaceWindowModel,
        // bypassing the 50ms debounce that coalesces rapid Hyprland events. This fires on
        // every agent/toplevel change for every inactive workspace pill currently visible —
        // during rapid window moves, this can execute tens of times per second. The clean fix
        // is to instantiate a WorkspaceWindowModel for root.ws and read its .model here, but
        // that adds one extra QtObject per pill slot and is deferred as a separate refactor.
        const windowModel = AppIconsProcessor.processClients(root.ws, Hypr.toplevels.values);
        const idxForPid = {};
        for (let i = 0; i < windowModel.length; i++) {
            for (const c of windowModel[i].clients) {
                const pid = c.lastIpcObject?.pid;
                if (pid !== undefined && pid !== null)
                    idxForPid[pid] = i;
            }
        }
        order.sort((a, b) => root._projectSortIndex(a, groups, idxForPid) - root._projectSortIndex(b, groups, idxForPid));

        return order.map(p => groups[p]);
    }

    /// Computes a project's sort index = earliest position among its agents' host windows.
    /// Projects whose host window isn't in the pid→index map sort to the end.
    function _projectSortIndex(projectName: string, groupsMap: var, pidIndexMap: var): int {
        // INT_MAX sentinel (fits a 32-bit QML int). Number.MAX_SAFE_INTEGER would be
        // ToInt32-coerced to -1 by the `: int` return type, wrongly sorting an unmatched
        // project (host window swallowed/closed) to the FRONT. Window indices are tiny,
        // so INT_MAX reliably sorts unmatched projects to the end.
        let min = 2147483647;
        for (const agent of groupsMap[projectName]) {
            const idx = pidIndexMap[agent.terminal_pid];
            if (idx !== undefined && idx < min)
                min = idx;
        }
        return min;
    }

    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth

    RowLayout {
        id: content

        anchors.centerIn: parent
        spacing: Appearance.spacing.small

        // Workspace label (Material icon or text)
        Loader {
            id: wsLabel

            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Config.bar.sizes.indicatorHeight
            sourceComponent: root.parsedIcon.useMaterial ? wsMatIcon : wsTextIcon

            Component {
                id: wsMatIcon

                MaterialIcon {
                    fill: 1
                    text: root.parsedIcon.iconText
                    color: root.labelColor
                    horizontalAlignment: Qt.AlignHCenter
                }
            }

            Component {
                id: wsTextIcon

                StyledText {
                    text: root.parsedIcon.iconText
                    color: root.labelColor
                    horizontalAlignment: Qt.AlignHCenter
                }
            }
        }

        // Window icons with each agent's project label + chip interleaved immediately to the
        // right of its host window (matched by terminal_pid → window pid): [icon] (name) ⭐.
        // The project name rides next to the agent it describes — not in a detached front
        // cluster — so multi-project workspaces stay legible. Active + occupied workspace only.
        // animateGroupWidth: false — the outer Layout.preferredWidth Behavior in
        // MergedBarContent.qml is the canonical width animator for the pill; inner group
        // animations would double-ease (same rationale as the old WorkspaceAppIcons usage).
        Loader {
            id: hostedRow

            Layout.alignment: Qt.AlignVCenter
            active: root.windowsVisible
            visible: active

            sourceComponent: MergedWindowAgentRow {
                workspaceId: root.ws
                agents: root.agents
                workspaceName: root.currentWorkspaceName
                animateGroupWidth: false
            }
        }

        // Trailing agent chips, grouped by project with their name label (AgentChipGroup):
        //  - active workspace: only agents whose host window isn't shown (swallowed/closed/
        //    not on this workspace) — so they never silently vanish.
        //  - inactive workspace (no window icons): all of this workspace's agents.
        Repeater {
            model: root._clusterGroups

            AgentChipGroup {
                // intentional var: JS array of one project's agents from _clusterGroups
                required property var modelData

                Layout.alignment: Qt.AlignVCenter
                agents: modelData
                workspaceName: root.currentWorkspaceName
            }
        }

        // Fullscreen/Maximize indicator - shared with the top-bar Workspace.qml.
        // Sits at the trailing edge of the active workspace slot, after app icons.
        WorkspaceFullscreenIndicator {
            wsId: root.ws
            isActive: root.isActive
        }
    }

    // Click handling: workspace label area switches/toggles workspace, rest focuses agent terminal.
    // Special workspaces use togglespecialworkspace (they overlay, not replace).
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: event => {
            const labelEnd = wsLabel.mapToItem(root, wsLabel.width, 0).x;
            if (event.x < labelEnd) {
                if (root.isSpecial) {
                    // Special workspaces toggle on/off as overlays
                    const name = root.currentWorkspace.name.slice("special:".length);
                    Hypr.dispatch(`togglespecialworkspace ${name}`);
                } else if (!root.isActive) {
                    if (root.ws < 0) {
                        const wsObj = Hypr.workspaceById(root.ws);
                        if (wsObj) Hypr.dispatch(`workspace name:${wsObj.name}`);
                    } else {
                        Hypr.dispatch(`workspace ${root.ws}`);
                    }
                }
            } else {
                const rep = AgentService.representativeAgent(root.agents);
                if (rep?.terminal_pid > 0)
                    AgentService.focusTerminal(rep.terminal_pid);
            }
        }
    }
}
