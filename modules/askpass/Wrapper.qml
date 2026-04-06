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

    shouldBeActive: visibilities.askpass && Config.askpass.enabled

    // Askpass doesn't constrain to maxHeight — it's always a fixed-size dialog
    maxHeight: screen.height
    clampToMaxHeight: false

    // Anchor content to bottom so it reveals top-down from the top edge
    anchorToTop: false

    contentComponent: Component {
        Content {
            screen: root.screen
            visibilities: root.visibilities

            Component.onCompleted: root.contentHeight = implicitHeight
        }
    }

    Connections {
        target: Config.askpass

        function onEnabledChanged(): void {
            root.configChanged();
        }
    }
}
