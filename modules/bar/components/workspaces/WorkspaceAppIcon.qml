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

    // Whether this client is the currently focused window
    readonly property bool isActive: {
        const activeAddr = Hypr.activeToplevel?.lastIpcObject?.address;
        const thisAddr = client.lastIpcObject?.address;
        return activeAddr && thisAddr && activeAddr === thisAddr;
    }
    // Hover state for tooltip
    property bool hovered: hoverHandler.hovered

    implicitWidth: Config.bar.sizes.innerWidth * 0.65
    implicitHeight: Config.bar.sizes.innerWidth * 0.65

    // Actual app icon from .desktop files
    IconImage {
        id: appIcon

        visible: Config.bar.workspaces.useActualAppIcons
        anchors.centerIn: parent
        implicitSize: Config.bar.sizes.innerWidth * 0.65
        source: Icons.resolveWindowIcon(
            root.client.lastIpcObject.class,
            Config.bar.workspaces.terminalAppDetection ? root.client.lastIpcObject.title : ""
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
        text: Icons.getAppCategoryIcon(root.client.lastIpcObject.class, "terminal")
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
            Hypr.dispatch(`focuswindow address:${root.client.lastIpcObject.address}`)
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
            text: root.client.lastIpcObject.title || root.client.lastIpcObject.class
        }
    }
}
