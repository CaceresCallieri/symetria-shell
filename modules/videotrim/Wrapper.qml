pragma ComponentBehavior: Bound

import qs.components.containers
import qs.services
import Quickshell
import QtQuick

/// Drawer wrapper for the video-trimmer panel.
///
/// Unlike the recorder drawer (which routes through the per-screen
/// `visibilities` map for merge-mode handoff), the trimmer is a transient modal
/// driven entirely by VideoTrimService. It binds `shouldBeActive` to the
/// service's `visible` flag AND a focused-monitor match, so the scrubber — and
/// its single decoding MediaPlayer — appears only on the screen that was
/// focused when the trim was requested, not duplicated across every monitor.
DrawerVertical {
    id: root

    required property ShellScreen screen

    shouldBeActive: VideoTrimService.visible && root.screen.name === VideoTrimService.targetScreen

    maxHeight: screen.height
    clampToMaxHeight: false

    // Top-hanging reveal (matches RecorderBackground / TopHangingBackground).
    anchorToTop: false

    contentComponent: Component {
        Content {
            Component.onCompleted: root.contentHeight = implicitHeight
        }
    }
}
