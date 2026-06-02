pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick

/// One project's agent chips, optionally preceded by the project-name label.
/// The label shows only when the project name differs from the host workspace's name —
/// when they match, the workspace icon already identifies the project. Pass workspaceName: ""
/// to always show the label (e.g. a remote slot with no local workspace).
///
/// All agents passed are assumed to belong to a single project (a terminal window hosts one
/// project's agents); the project is read from the first agent. Collapses to zero width when
/// there are no agents, so an agentless host window adds no trailing gap.
Row {
    id: root

    // intentional var: agent JS objects (one project) from AgentService bridge JSON
    required property var agents
    /// Workspace name to compare against; "" means "always show the label".
    property string workspaceName: ""

    readonly property string project: root.agents.length > 0 ? (root.agents[0].project ?? "") : ""
    readonly property bool showName: root.project !== "" && root.project !== root.workspaceName

    spacing: Appearance.spacing.smaller
    visible: root.agents.length > 0

    // Project name — sits before the chip(s): [icon] (project name) ⭐ when used inside
    // HostedAgentIcon, or (project name) ⭐ standalone in the trailing cluster.
    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.showName
        text: root.project
        color: Colours.palette.m3primary
        font.weight: Font.Bold
        font.pointSize: Appearance.font.size.small
    }

    Repeater {
        model: root.agents

        AgentChipFor {
            // intentional var: heterogeneous agent JS object from bridge JSON
            required property var modelData

            anchors.verticalCenter: parent.verticalCenter
            agent: modelData
        }
    }
}
