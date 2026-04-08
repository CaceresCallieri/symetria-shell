pragma ComponentBehavior: Bound

import qs.components.containers
import qs.config
import qs.services
import Quickshell
import QtQuick

/// Drawer wrapper for the recorder module.
///
/// Uses DrawerVertical for the slide-down animation. Merge mode is handled
/// implicitly: RecorderRoot.qml sets visibilities.recorder = false when merge
/// activates, which makes shouldBeActive false → drawer animates closed.
DrawerVertical {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities
    required property var panels

    shouldBeActive: visibilities.recorder && Config.audioRecorder.enabled

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
}
