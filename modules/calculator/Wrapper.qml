pragma ComponentBehavior: Bound

import qs.components.containers
import qs.config
import Quickshell
import QtQuick

/// Calculator drawer wrapper handling lifecycle, animations, and pre-loading.
///
/// Positioned at bottom-center of the screen, rising upward when visible.
/// Uses the DrawerVertical base component for shared animation logic.
DrawerVertical {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities
    required property var panels

    shouldBeActive: visibilities.calculator && Config.calculator.enabled

    maxHeight: {
        let max = screen.height - Config.border.thickness * 2 - Appearance.spacing.large;
        // Account for launcher if open (mutual exclusion means this shouldn't happen often)
        if (visibilities.launcher)
            max -= panels.launcher.height + Appearance.spacing.large;
        // Account for clipboard if open
        if (visibilities.clipboard)
            max -= panels.clipboard.height + Appearance.spacing.large;
        return max;
    }

    contentComponent: Component {
        Content {
            visibilities: root.visibilities
            panels: root.panels
            maxHeight: root.maxHeight

            Component.onCompleted: root.contentHeight = implicitHeight
        }
    }

    Connections {
        target: Config.calculator

        function onEnabledChanged(): void {
            root.configChanged();
        }

        function onMaxHistoryChanged(): void {
            root.configChanged();
        }
    }
}
