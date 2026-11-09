pragma ComponentBehavior: Bound

import qs.components.containers
import qs.config
import qs.services
import Quickshell
import QtQuick

/// Drawer wrapper for the recorder module.
///
/// Uses DrawerVertical for the slide-down animation. The drawer is the only
/// recorder surface: it opens and closes purely through
/// visibilities.recorder, which RecorderRoot derives from the Mesura
/// session state.
///
/// Handles both audio recorder and STT modes — the Content component
/// determines which mode-specific UI to show based on RecordingSessionManager.
DrawerVertical {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities

    shouldBeActive: visibilities.recorder

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
