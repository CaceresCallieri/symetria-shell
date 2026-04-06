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

    shouldBeActive: visibilities.packages && Config.packages.enabled

    maxHeight: screen.height - Config.border.thickness * 2 - Appearance.spacing.large

    // Anchor content to bottom so it reveals top-down from the top edge
    anchorToTop: false

    contentComponent: Component {
        Content {
            visibilities: root.visibilities
            maxHeight: root.maxHeight

            Component.onCompleted: root.contentHeight = implicitHeight
        }
    }

    Connections {
        target: Config.packages

        function onEnabledChanged(): void {
            root.configChanged();
        }
    }

    // Restore focus when Content is recreated while packages is active
    onContentItemChanged: {
        if (contentItem && shouldBeActive && typeof contentItem.focusSearch === "function")
            contentItem.focusSearch();
    }
}
