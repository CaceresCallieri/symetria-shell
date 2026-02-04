import qs.config
import qs.modules.osd as Osd
import qs.modules.notifications as Notifications
import qs.modules.session as Session
import qs.modules.launcher as Launcher
import qs.modules.dashboard as Dashboard
import qs.modules.bar.popouts as BarPopouts
import qs.modules.utilities as Utilities
import qs.modules.utilities.toasts as Toasts
import qs.modules.sidebar as Sidebar
import qs.modules.clipboard as ClipboardModule
import qs.modules.askpass as Askpass
import qs.modules.hyprwhspr as HyprWhsprModule
import qs.modules.keycaster as KeycasterModule
import Quickshell
import QtQuick

Item {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities
    required property Item bar

    readonly property alias osd: osd
    readonly property alias notifications: notifications
    readonly property alias session: session
    readonly property alias launcher: launcher
    readonly property alias dashboard: dashboard
    readonly property alias popouts: popouts
    readonly property alias utilities: utilities
    readonly property alias toasts: toasts
    readonly property alias sidebar: sidebar
    readonly property alias clipboard: clipboard
    readonly property alias askpass: askpass
    readonly property alias hyprwhspr: hyprwhspr
    readonly property alias keycaster: keycaster

    anchors.fill: parent
    anchors.margins: Config.border.thickness
    anchors.topMargin: bar.implicitHeight

    Osd.Wrapper {
        id: osd

        clip: session.width > 0 || sidebar.width > 0
        screen: root.screen
        visibilities: root.visibilities

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: session.width + sidebar.width
    }

    Notifications.Wrapper {
        id: notifications

        visibilities: root.visibilities
        panels: root

        anchors.top: parent.top
        anchors.right: parent.right
    }

    Session.Wrapper {
        id: session

        clip: sidebar.width > 0
        visibilities: root.visibilities
        panels: root

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: sidebar.width
    }

    Launcher.Wrapper {
        id: launcher

        screen: root.screen
        visibilities: root.visibilities
        panels: root

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
    }

    ClipboardModule.Wrapper {
        id: clipboard

        screen: root.screen
        visibilities: root.visibilities
        panels: root

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: launcher.height > 0 ? launcher.height + Appearance.spacing.large : 0
    }

    Dashboard.Wrapper {
        id: dashboard

        visibilities: root.visibilities

        anchors.left: parent.left
        anchors.bottom: parent.bottom
    }

    Askpass.Wrapper {
        id: askpass

        screen: root.screen
        visibilities: root.visibilities
        panels: root

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
    }

    HyprWhsprModule.Wrapper {
        id: hyprwhspr

        screen: root.screen
        visibilities: root.visibilities
        panels: root

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
    }

    KeycasterModule.Wrapper {
        id: keycaster

        screen: root.screen
        visibilities: root.visibilities
        panels: root

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Appearance.spacing.large
    }

    BarPopouts.Wrapper {
        id: popouts

        screen: root.screen

        x: {
            if (isDetached)
                return (root.width - nonAnimWidth) / 2;

            const off = currentCenter - Config.border.thickness - nonAnimWidth / 2;
            const diff = root.width - Math.floor(off + nonAnimWidth);
            if (diff < 0)
                return off + diff;
            return Math.max(off, 0);
        }
        y: isDetached ? (root.height - nonAnimHeight) / 2 : 0
    }

    Utilities.Wrapper {
        id: utilities

        visibilities: root.visibilities
        sidebar: sidebar
        popouts: popouts

        anchors.bottom: parent.bottom
        anchors.right: parent.right
    }

    Toasts.Toasts {
        id: toasts

        anchors.bottom: sidebar.visible ? parent.bottom : utilities.top
        anchors.right: sidebar.left
        anchors.margins: Appearance.padding.normal
    }

    Sidebar.Wrapper {
        id: sidebar

        visibilities: root.visibilities
        panels: root

        anchors.top: notifications.bottom
        anchors.bottom: utilities.top
        anchors.right: parent.right
    }
}
