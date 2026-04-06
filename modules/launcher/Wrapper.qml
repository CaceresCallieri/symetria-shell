pragma ComponentBehavior: Bound

import qs.components.containers
import qs.config
import Quickshell
import QtQuick

DrawerVertical {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities
    required property var panels

    shouldBeActive: visibilities.launcher && Config.launcher.enabled

    // Dashboard moved to bottom-left corner, no longer vertically constrains launcher
    maxHeight: screen.height - Config.border.thickness * 2 - Appearance.spacing.large

    contentComponent: Component {
        Content {
            visibilities: root.visibilities
            panels: root.panels
            maxHeight: root.maxHeight

            Component.onCompleted: root.contentHeight = implicitHeight
        }
    }

    Connections {
        target: Config.launcher

        function onEnabledChanged(): void {
            root.configChanged();
        }

        function onMaxShownChanged(): void {
            root.configChanged();
        }
    }

    Connections {
        target: DesktopEntries.applications

        function onValuesChanged(): void {
            if (DesktopEntries.applications.values.length < Config.launcher.maxShown)
                root.configChanged();
        }
    }

    // Restore focus when Content is recreated while launcher is active
    // (Timer-based recreation can destroy/recreate Content mid-typing)
    onContentItemChanged: {
        if (contentItem && shouldBeActive && typeof contentItem.focusSearch === "function")
            contentItem.focusSearch();
    }
}
