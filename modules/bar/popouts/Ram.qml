pragma ComponentBehavior: Bound

import "root:utils" as Utils
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
    // Width for workspace icon column (accommodates Roman numerals up to "VIII")
    readonly property int workspaceIconWidth: 24

    spacing: Appearance.spacing.normal
    width: Config.bar.sizes.updatesWidth

    // PID→workspace cache: rebuilt every 3s (same cadence as ProcessMemory updates).
    // Inverts the O(n×m) lookup (50 processes × all toplevels per call) to O(m) build + O(1) lookups.
    property var _pidWorkspaceCache: ({})

    // Subscribe to ProcessMemory for top process data
    Ref {
        service: ProcessMemory
    }

    /// Look up workspace for a process PID via cached toplevel data.
    /// Cache is rebuilt by _cacheRebuildTimer every 3 seconds.
    /// @param pid Process ID to search for
    /// @returns {id, name} object or null for background processes
    function getWorkspaceForPid(pid: int): var {
        if (!pid) return null;
        return _pidWorkspaceCache[pid] ?? null;
    }

    Timer {
        id: _cacheRebuildTimer
        interval: 3000
        repeat: true
        running: ProcessMemory.topProcesses.length > 0
        triggeredOnStart: true
        onTriggered: {
            const cache = {};
            for (const toplevel of Hypr.toplevels.values) {
                const ipc = toplevel.lastIpcObject;
                if (ipc?.pid && ipc?.workspace) {
                    cache[ipc.pid] = {
                        id: ipc.workspace.id,
                        name: ipc.workspace.name
                    };
                }
            }
            root._pidWorkspaceCache = cache;
        }
    }

    /// Convert workspace to display icon (Roman numeral or Material icon)
    /// @param workspace Workspace object with id and name properties
    /// @returns Icon string - plain text or "mat:icon_name" format for Material icons
    function getWorkspaceIcon(workspace: var): string {
        if (!workspace) return "";

        // Special workspaces (negative ID)
        if (workspace.id < 0) {
            if (workspace.name.startsWith("special:")) {
                // Special workspace - use configured icon with fallbacks
                return Utils.Icons.getSpecialWsIcon(workspace.name);
            }
            // Named workspace - try custom icon, fall back to first letter
            const icon = Utils.Icons.getNamedWsIcon(workspace.name);
            return icon || (workspace.name?.[0]?.toUpperCase() ?? "");
        }

        // Regular numeric workspace - convert to Roman numeral
        return Utils.Icons.romanize(workspace.id);
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
            reuseItems: true  // Essential: recycles delegates for 50-item list performance

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

    /// Reusable row component for displaying a process with memory info
    component ProcessRow: RowLayout {
        id: processRow

        // --- Required properties (from model) ---
        required property string name
        required property int pid
        required property int memoryKib
        required property var memoryFormatted

        // --- Computed properties ---
        readonly property real memPercent: SystemUsage.memTotal > 0
            ? (memoryKib / SystemUsage.memTotal) * 100
            : 0

        // Workspace lookup and icon resolution
        readonly property var workspace: root.getWorkspaceForPid(pid)
        readonly property string workspaceIcon: root.getWorkspaceIcon(workspace)
        readonly property var parsedIcon: Utils.Icons.parseIcon(workspaceIcon)
        readonly property bool useMaterialIcon: parsedIcon.useMaterial

        spacing: Appearance.spacing.small

        // Workspace indicator column (fixed width for alignment)
        // Shows icon when process has a visible window, empty otherwise
        Item {
            Layout.preferredWidth: root.workspaceIconWidth
            Layout.alignment: Qt.AlignVCenter

            MaterialIcon {
                anchors.centerIn: parent
                visible: processRow.workspaceIcon.length > 0 && processRow.useMaterialIcon
                text: processRow.parsedIcon.iconText
                fill: 1
                font.pointSize: Appearance.font.size.smaller
                color: Colours.palette.m3secondary
            }

            StyledText {
                anchors.centerIn: parent
                visible: processRow.workspaceIcon.length > 0 && !processRow.useMaterialIcon
                text: processRow.parsedIcon.iconText
                font.family: Appearance.font.family.mono
                font.pointSize: Appearance.font.size.smaller
                color: Colours.palette.m3secondary
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // Process name (expands to fill available space)
        StyledText {
            Layout.fillWidth: true
            text: processRow.name
            elide: Text.ElideRight
        }

        // Memory usage value
        StyledText {
            text: `${processRow.memoryFormatted.value.toFixed(1)} ${processRow.memoryFormatted.unit}`
            font.family: Appearance.font.family.mono
            font.pointSize: Appearance.font.size.small
            horizontalAlignment: Text.AlignRight
        }

        // Memory percentage
        StyledText {
            Layout.preferredWidth: 45
            text: `${processRow.memPercent.toFixed(1)}%`
            font.family: Appearance.font.family.mono
            font.pointSize: Appearance.font.size.small
            opacity: 0.7
            horizontalAlignment: Text.AlignRight
        }
    }
}
