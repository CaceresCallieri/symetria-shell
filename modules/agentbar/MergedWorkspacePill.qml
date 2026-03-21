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
    required property int activeWsId   // Actually visualActiveWsId from MergedBarContent
    required property var agents       // Array of agent objects on this workspace
    required property var occupied     // { [wsId]: bool } map

    // ActiveIndicator contract — matches Workspace.qml's interface
    readonly property bool isWorkspace: true
    readonly property int ws: wsId
    readonly property bool isActive: activeWsId === ws
    readonly property int activePadding: Appearance.padding.large
    readonly property int indicatorOffset: isActive ? activePadding : 0
    readonly property int indicatorSize: implicitWidth + (isActive ? activePadding * 2 : 0)

    // Workspace state
    readonly property bool isOccupied: occupied[ws] ?? false

    // Special workspace detection
    readonly property var currentWorkspace: Hypr.workspaces.values.find(w => w.id === root.ws) ?? null
    readonly property bool isSpecial: currentWorkspace?.name.startsWith("special:") ?? false

    // Icon resolution: special → getSpecialWsIcon, named → getNamedWsIcon, numbered → romanize
    // Uses AgentService.workspaceIconForWsId() which already handles all three cases.
    readonly property string rawIcon: AgentService.workspaceIconForWsId(root.ws)
    readonly property var parsedIcon: Icons.parseIcon(rawIcon)

    // Color: active uses onSurface, inactive uses muted variant
    readonly property color labelColor: isActive ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant

    // Group agents by project for display: [{project: "foo", agents: [...]}]
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

        // Agent groups: project name + chips, grouped by project
        Repeater {
            model: root._projectGroups

            RowLayout {
                required property var modelData

                Layout.alignment: Qt.AlignVCenter
                spacing: Appearance.spacing.smaller

                // Project name label
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: modelData.project
                    color: Colours.palette.m3primary
                    font.weight: Font.Bold
                    font.pointSize: Appearance.font.size.small
                }

                // Agent chips for this project
                Repeater {
                    model: modelData.agents

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

        // App icons (active workspace only).
        // visible must track active so the RowLayout collapses the slot to zero width.
        // Special workspaces use a separate config flag (showWindowsOnSpecialWorkspaces).
        Loader {
            Layout.alignment: Qt.AlignVCenter
            active: root.isActive && root.isOccupied
                && (root.isSpecial ? Config.bar.workspaces.showWindowsOnSpecialWorkspaces : Config.bar.workspaces.showWindows)
            visible: active

            sourceComponent: MergedAppIcons {
                workspaceId: root.ws
            }
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
                        const wsObj = Hypr.workspaces.values.find(w => w.id === root.ws);
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
