pragma ComponentBehavior: Bound

import qs.components
import qs.config
import Quickshell.Hyprland
import QtQuick

/// One window's app icon followed by the agent chip(s) hosted inside it.
/// "Hosted" = the agent's terminal_pid matches this window's pid. Used by
/// MergedWindowAgentRow for both ungrouped windows and members of a tab group,
/// so the icon→chip pairing has a single definition.
Row {
    id: root

    required property HyprlandToplevel client
    // intentional var: agent JS objects whose terminal_pid === this window's pid
    required property var hostedAgents
    property bool animateEntry: true

    spacing: Appearance.padding.small

    ClientAppIcon {
        anchors.verticalCenter: parent.verticalCenter
        client: root.client
        animateEntry: root.animateEntry
    }

    // Chips ride immediately to the right of the icon — this is the "where the agent lives"
    // pairing. Usually 0 or 1, but a window can host several agents (e.g. split panes).
    Repeater {
        model: root.hostedAgents

        AgentChipFor {
            required property var modelData

            anchors.verticalCenter: parent.verticalCenter
            agent: modelData
        }
    }
}
