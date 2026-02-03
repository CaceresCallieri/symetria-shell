pragma ComponentBehavior: Bound

import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.misc
import qs.services
import qs.config
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

Column {
    id: root

    // Scroll configuration: show 8 visible items at a time
    readonly property int visibleItems: 8
    // Estimate item height based on font size and spacing
    readonly property real itemHeight: Appearance.font.size.small * 2.5 + Appearance.spacing.small
    readonly property real maxListHeight: visibleItems * (itemHeight + Appearance.spacing.small)

    spacing: Appearance.spacing.normal
    width: Config.bar.sizes.updatesWidth

    // Subscribe to ProcessMemory for top process data
    Ref {
        service: ProcessMemory
    }

    // Look up workspace for a process PID by searching Hyprland toplevels
    // Returns workspace name/id or null if not found (background process)
    function getWorkspaceForPid(pid: int): var {
        if (!pid) return null;

        // Search all toplevels for matching PID
        for (const toplevel of Hypr.toplevels.values) {
            const ipc = toplevel.lastIpcObject;
            if (ipc && ipc.pid === pid) {
                // Return workspace info
                const ws = ipc.workspace;
                if (ws) {
                    return {
                        id: ws.id,
                        name: ws.name
                    };
                }
            }
        }
        return null;
    }

    // Format workspace display string
    function formatWorkspace(workspace: var): string {
        if (!workspace) return "";

        // Special workspaces have negative IDs and descriptive names
        if (workspace.id < 0) {
            // Extract readable name from "special:name" format
            const name = workspace.name;
            if (name.startsWith("special:")) {
                return name.slice(8); // Remove "special:" prefix
            }
            return name;
        }

        // Regular workspaces - just show the number/name
        return workspace.name || workspace.id.toString();
    }

    // Header: RAM summary
    RowLayout {
        width: parent.width
        spacing: Appearance.spacing.normal

        MaterialIcon {
            text: "memory_alt"
            color: Colours.palette.m3primary
            font.pointSize: Appearance.font.size.large
        }

        Column {
            Layout.fillWidth: true
            spacing: Appearance.spacing.smaller

            StyledText {
                readonly property var memUsed: SystemUsage.formatKib(SystemUsage.memUsed)
                readonly property var memTotal: SystemUsage.formatKib(SystemUsage.memTotal)

                text: `${memUsed.value.toFixed(1)} ${memUsed.unit} / ${memTotal.value.toFixed(1)} ${memTotal.unit}`
                font.pointSize: Appearance.font.size.normal
                font.weight: 500
            }

            StyledText {
                text: qsTr("Memory Usage: %1%").arg(Math.round(SystemUsage.memPerc * 100))
                font.pointSize: Appearance.font.size.small
                opacity: 0.8
            }
        }
    }

    // Separator
    Rectangle {
        width: parent.width
        height: 1
        color: Colours.palette.m3outline
        opacity: 0.3
    }

    // Header for process list
    StyledText {
        width: parent.width
        text: qsTr("Top Memory Usage")
        font.weight: 500
        opacity: 0.8
        horizontalAlignment: Text.AlignHCenter
    }

    // Scrollable process list
    Item {
        width: parent.width
        height: ProcessMemory.topProcesses.length > 0
            ? Math.min(processList.contentHeight, root.maxListHeight)
            : loadingText.implicitHeight

        StyledListView {
            id: processList

            visible: ProcessMemory.topProcesses.length > 0
            model: ProcessMemory.topProcesses
            width: parent.width
            height: Math.min(contentHeight, root.maxListHeight)
            clip: true
            spacing: Appearance.spacing.small
            reuseItems: true

            delegate: ProcessRow {
                required property var modelData
                required property int index

                width: processList.width
                pid: modelData.pid
                name: modelData.name
                memoryKib: modelData.memoryKib
                memoryFormatted: modelData.memoryFormatted
            }

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: processList
            }
        }

        // Loading state
        StyledText {
            id: loadingText

            visible: ProcessMemory.topProcesses.length === 0
            text: qsTr("Loading...")
            font.pointSize: Appearance.font.size.small
            opacity: 0.6
        }
    }

    // Reusable row component for processes
    component ProcessRow: RowLayout {
        required property string name
        required property int pid
        required property int memoryKib
        required property var memoryFormatted

        readonly property real memPercent: SystemUsage.memTotal > 0
            ? (memoryKib / SystemUsage.memTotal) * 100
            : 0
        readonly property var workspace: root.getWorkspaceForPid(pid)
        readonly property string workspaceText: root.formatWorkspace(workspace)

        spacing: Appearance.spacing.small

        // Workspace indicator (only if process has a window)
        StyledText {
            Layout.preferredWidth: 24
            visible: parent.workspaceText.length > 0
            text: parent.workspaceText
            font.family: Appearance.font.family.mono
            font.pointSize: Appearance.font.size.smaller
            color: Colours.palette.m3secondary
            horizontalAlignment: Text.AlignCenter
        }

        // Empty spacer when no workspace
        Item {
            Layout.preferredWidth: 24
            visible: parent.workspaceText.length === 0
        }

        StyledText {
            Layout.fillWidth: true
            text: parent.name
            elide: Text.ElideRight
        }

        StyledText {
            text: `${parent.memoryFormatted.value.toFixed(1)} ${parent.memoryFormatted.unit}`
            font.family: Appearance.font.family.mono
            font.pointSize: Appearance.font.size.small
            horizontalAlignment: Text.AlignRight
        }

        StyledText {
            Layout.preferredWidth: 45
            text: `${parent.memPercent.toFixed(1)}%`
            font.family: Appearance.font.family.mono
            font.pointSize: Appearance.font.size.small
            opacity: 0.7
            horizontalAlignment: Text.AlignRight
        }
    }
}
