pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.config
import Quickshell
import Quickshell.Widgets
import QtQuick

/// Individual app icon for the merged bar (mirrors WorkspaceAppIcon).
Item {
    id: root

    required property var client
    property bool animateEntry: true

    readonly property bool hasValidClient: (client?.lastIpcObject?.class ?? "") !== ""
    visible: hasValidClient

    readonly property bool isActive: {
        const activeAddr = Hypr.activeToplevel?.lastIpcObject?.address;
        const thisAddr = client?.lastIpcObject?.address;
        return Boolean(activeAddr && thisAddr && activeAddr === thisAddr);
    }

    property bool hovered: hoverHandler.hovered

    implicitWidth: Config.bar.sizes.iconSize
    implicitHeight: Config.bar.sizes.iconSize

    scale: animateEntry ? 0 : 1
    Component.onCompleted: if (animateEntry) scale = 1

    Behavior on scale {
        enabled: root.animateEntry
        Anim {
            easing.bezierCurve: Appearance.anim.curves.standardDecel
        }
    }

    IconImage {
        visible: Config.bar.workspaces.useActualAppIcons
        anchors.centerIn: parent
        implicitSize: Math.max(Config.bar.sizes.iconSize, 16)
        source: Icons.resolveWindowIcon(
            root.client?.lastIpcObject?.class ?? "",
            Config.bar.workspaces.terminalAppDetection ? (root.client?.lastIpcObject?.title ?? "") : ""
        )
        opacity: root.isActive ? 1.0 : 0.7

        Behavior on opacity {
            Anim { duration: Appearance.anim.durations.small }
        }
    }

    MaterialIcon {
        visible: !Config.bar.workspaces.useActualAppIcons
        anchors.centerIn: parent
        grade: 0
        text: Icons.getAppCategoryIcon(root.client?.lastIpcObject?.class ?? "", "terminal")
        color: Colours.palette.m3onSurfaceVariant
        opacity: root.isActive ? 1.0 : 0.7

        Behavior on opacity {
            Anim { duration: Appearance.anim.durations.small }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: Config.bar.workspaces.appIconsClickToFocus
        cursorShape: Config.bar.workspaces.appIconsClickToFocus ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            const addr = root.client?.lastIpcObject?.address;
            if (addr) Hypr.dispatch(`focuswindow address:${addr}`)
        }
    }

    HoverHandler {
        id: hoverHandler
    }

    Loader {
        active: root.hovered
        asynchronous: true

        sourceComponent: Tooltip {
            target: root
            text: root.client?.lastIpcObject?.title || root.client?.lastIpcObject?.class || ""
        }
    }
}
