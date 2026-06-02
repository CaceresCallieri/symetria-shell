pragma ComponentBehavior: Bound

import qs.components
import qs.config
import Quickshell.Hyprland
import QtQuick

/// One window's app icon followed by the project label + agent chip(s) hosted inside it,
/// laid out as: [icon] (project name) ⭐. "Hosted" = the agent's terminal_pid matches this
/// window's pid. Used by MergedWindowAgentRow for both ungrouped windows and members of a
/// tab group, so the icon→label→chip pairing has a single definition.
Row {
    id: root

    required property HyprlandToplevel client
    // intentional var: agent JS objects whose terminal_pid === this window's pid
    required property var hostedAgents
    /// Forwarded to AgentChipGroup for the project-label visibility rule (hide when == ws name).
    required property string workspaceName
    property bool animateEntry: true

    spacing: Appearance.padding.small

    ClientAppIcon {
        anchors.verticalCenter: parent.verticalCenter
        client: root.client
        animateEntry: root.animateEntry
    }

    // Project name + chip(s) for the agents living in this window — sits to the right of the
    // icon. AgentChipGroup hides the name when it matches the workspace name and collapses
    // entirely when this window hosts no agents (so a plain window adds no trailing gap).
    AgentChipGroup {
        anchors.verticalCenter: parent.verticalCenter
        agents: root.hostedAgents
        workspaceName: root.workspaceName
    }
}
