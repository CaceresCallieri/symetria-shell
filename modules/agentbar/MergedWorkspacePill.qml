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

/// Per-workspace slot in the merged bar: workspace label + project names + agent chips + app icons.
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
    readonly property int indicatorOffset: isActive ? activePadding : 0
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

    // Group agents by project for display: [{project: "foo", agents: [...]}]
    // intentional var: JS array of heterogeneous objects built with .map()
    readonly property var _projectGroups: {
        const groups = {};
        const order = [];
        for (const agent of root.agents) {
            const p = agent.project ?? "unknown";
            if (!groups[p]) {
                groups[p] = [];
                order.push(p);
            }
            groups[p].push(agent);
        }
        return order.map(p => ({ project: p, agents: groups[p] }));
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

        // Project name labels (no chips — chips now ride next to their host window icon).
        // One label per project present on this workspace; hidden when the project name
        // matches the workspace name (the workspace icon already identifies it).
        // currentWorkspaceName is "" until Hyprland reports the workspace — the label always
        // shows in that transient state.
        Repeater {
            model: root._projectGroups

            StyledText {
                // intentional var: JS object { project: string, agents: [] } from _projectGroups
                required property var modelData

                Layout.alignment: Qt.AlignVCenter
                text: modelData.project
                color: Colours.palette.m3primary
                font.weight: Font.Bold
                font.pointSize: Appearance.font.size.small
                visible: modelData.project !== root.currentWorkspaceName
            }
        }

        // Window icons with each agent's chip interleaved immediately to the right of its
        // host window (matched by terminal_pid → window pid) — the "where the agent lives"
        // layout. Active + occupied workspace only.
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
                animateGroupWidth: false
            }
        }

        // Trailing agent chips:
        //  - active workspace: only agents whose host window isn't shown (swallowed/closed/
        //    not on this workspace) — so they never silently vanish.
        //  - inactive workspace (no window icons): all of this workspace's agents, clustered.
        Repeater {
            model: root.windowsVisible
                ? (hostedRow.item?.unmatchedAgents ?? [])
                : root.agents

            AgentChipFor {
                // intentional var: heterogeneous agent JS object from bridge JSON
                required property var modelData

                Layout.alignment: Qt.AlignVCenter
                agent: modelData
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
