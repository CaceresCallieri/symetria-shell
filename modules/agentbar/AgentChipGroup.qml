pragma ComponentBehavior: Bound

import qs.config
import Quickshell
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

    // All agents in the array belong to the same project (the caller — _clusterGroups or
    // _agentsByPid — groups them by project before passing them here). Reading [0].project
    // is therefore representative; the value does not change within the group.
    readonly property string project: root.agents.length > 0 ? (root.agents[0].project ?? "") : ""
    readonly property bool showName: root.project !== "" && root.project !== root.workspaceName

    spacing: Appearance.spacing.smaller
    visible: root.agents.length > 0

    // Project name — sits before the chip(s): [icon] (project name) ⭐ when used inside
    // HostedAgentIcon, or (project name) ⭐ standalone in the trailing cluster.
    ProjectNameLabel {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.showName
        text: root.project
    }

    Repeater {
        // ScriptModel keyed on the stable agent id (NOT a plain JS array). AgentService
        // replaces _agents with freshly-parsed objects on every bridge emission; a plain
        // array is opaque to Qt, forcing a FULL model reset (all delegates destroyed +
        // recreated) each time. During each reset, idle siblings' delegates are recreated
        // and briefly flash a busy sparkle — most visible with OpenCode, which re-emits on
        // every tool call. objectProp:"id" lets ScriptModel match same-id objects across
        // emissions and update delegates in place, so a churning agent never re-renders its
        // idle siblings. See docs/qml-pitfalls.md (agent-chip delegate identity).
        model: ScriptModel {
            values: root.agents
            objectProp: "id"
        }

        AgentChipFor {
            // intentional var: heterogeneous agent JS object from bridge JSON
            required property var modelData

            // parent?. (not parent.) — a Repeater delegate root evaluates its bindings
            // once before it is reparented, so the bare form throws on every creation.
            // See docs/qml-pitfalls.md (Repeater delegate's parent is null).
            anchors.verticalCenter: parent?.verticalCenter
            agent: modelData
        }
    }
}
