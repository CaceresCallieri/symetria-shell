pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.config
import Quickshell
import Quickshell.Widgets
import QtQuick

// Individual app icon for workspace display
// Shows actual app icon with click-to-focus and tooltip
Item {
    id: root

    required property var client // HyprlandToplevel
    property bool animateEntry: true // Whether to animate entry (disabled for grouped icons)

    // Hide when client data becomes invalid (prevents fallback icon flash on close)
    readonly property bool hasValidClient: (client?.lastIpcObject?.class ?? "") !== ""
    visible: hasValidClient

    // Whether this client is the currently focused window
    readonly property bool isActive: {
        const activeAddr = Hypr.activeToplevel?.lastIpcObject?.address;
        const thisAddr = client?.lastIpcObject?.address;
        return Boolean(activeAddr && thisAddr && activeAddr === thisAddr);
    }
    // Hover state for tooltip
    property bool hovered: hoverHandler.hovered

    implicitWidth: Config.bar.sizes.iconSize
    implicitHeight: Config.bar.sizes.iconSize

    // Entry animation - scale in when added (only for ungrouped icons)
    scale: animateEntry ? 0 : 1
    Component.onCompleted: if (animateEntry) scale = 1

    Behavior on scale {
        enabled: root.animateEntry
        Anim {
            easing.bezierCurve: Appearance.anim.curves.standardDecel
        }
    }

    // Actual app icon from .desktop files
    IconImage {
        id: appIcon

        visible: Config.bar.workspaces.useActualAppIcons
        anchors.centerIn: parent
        // Minimum 16px to prevent invalid icon requests during initialization
        implicitSize: Math.max(Config.bar.sizes.iconSize, 16)
        source: Icons.resolveWindowIcon(
            root.client?.lastIpcObject?.class ?? "",
            Config.bar.workspaces.terminalAppDetection ? (root.client?.lastIpcObject?.title ?? "") : ""
        )

        // Visual indicator for active window
        opacity: root.isActive ? 1.0 : 0.7

        Behavior on opacity {
            Anim {
                duration: Appearance.anim.durations.small
            }
        }
    }

    // Fallback: Material category icon (when useActualAppIcons is false)
    MaterialIcon {
        id: categoryIcon

        visible: !Config.bar.workspaces.useActualAppIcons
        anchors.centerIn: parent
        grade: 0
        text: Icons.getAppCategoryIcon(root.client?.lastIpcObject?.class ?? "", "terminal")
        color: Colours.palette.m3onSurfaceVariant

        opacity: root.isActive ? 1.0 : 0.7

        Behavior on opacity {
            Anim {
                duration: Appearance.anim.durations.small
            }
        }
    }

    // Click to focus the window (when enabled)
    MouseArea {
        anchors.fill: parent
        enabled: Config.bar.workspaces.appIconsClickToFocus
        cursorShape: Config.bar.workspaces.appIconsClickToFocus ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            const addr = root.client?.lastIpcObject?.address;
            if (addr) Hypr.dispatch(`focuswindow address:${addr}`)
        }
    }

    // Hover detection for tooltip
    HoverHandler {
        id: hoverHandler
    }

    // Tooltip showing window title (lazy-loaded for performance)
    Loader {
        active: root.hovered
        asynchronous: true

        sourceComponent: Tooltip {
            target: root
            text: root.client?.lastIpcObject?.title || root.client?.lastIpcObject?.class || ""
        }
    }
}
