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

    // Persistent state for clipboard tabs (survives drawer close/open)
    readonly property PersistentProperties clipState: PersistentProperties {
        property int currentTab: 0  // 0=Text, 1=Images
        reloadableId: "clipboardState"
    }

    shouldBeActive: visibilities.clipboard && Config.clipboard.enabled

    maxHeight: {
        let max = screen.height - Config.border.thickness * 2 - Appearance.spacing.large;
        // Account for launcher if open.
        // NOTE: This creates cross-module coupling - when launcher height changes
        // (e.g., user typing filters results), onMaxHeightChanged fires, triggering
        // Timer-based Content pre-loading. Clipboard's Content.qml has visibility
        // guards to prevent focus stealing during pre-loading.
        if (visibilities.launcher)
            max -= panels.launcher.height + Appearance.spacing.large;
        return max;
    }

    contentComponent: Component {
        Content {
            visibilities: root.visibilities
            panels: root.panels
            maxHeight: root.maxHeight
            state: root.clipState

            Component.onCompleted: root.contentHeight = implicitHeight
        }
    }

    Connections {
        target: Config.clipboard

        function onEnabledChanged(): void {
            root.configChanged();
        }

        function onMaxShownChanged(): void {
            root.configChanged();
        }
    }
}
