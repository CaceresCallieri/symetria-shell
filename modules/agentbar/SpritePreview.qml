pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick

/// Right-aligned sprite preview for testing animations in the agentbar.
/// Controlled by the /test-sprite skill — edit the properties below, clear cache, restart.
Row {
    id: root

    // ── Skill-managed properties ─────────────────────────────────────
    property bool previewActive: false
    property string previewMode: "key-morph"
    property string chainMode: ""   // optional: play this mode after previewMode completes
    property int holdMs: 1200       // pause before restarting one-shot animations
    property real speed: 1.0
    // ── End skill-managed ────────────────────────────────────────────

    visible: previewActive
    spacing: 4

    property string _currentMode: previewMode

    ClaudeSparkle {
        id: sparkle
        anchors.verticalCenter: parent.verticalCenter
        color: "#d97757"
        mode: root._currentMode
        speedFactor: root.speed
        onAnimationComplete: {
            if (root.chainMode && root._currentMode === root.previewMode) {
                // Phase 1 complete → transition to chain mode
                root._currentMode = root.chainMode
            } else {
                // Final phase complete → hold then restart
                holdTimer.start()
            }
        }
    }

    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        text: root._currentMode
        color: "#d97757"
        font.family: Appearance.font.family.mono
        font.pointSize: Appearance.font.size.small
    }

    Timer {
        id: holdTimer
        interval: root.holdMs
        onTriggered: {
            root._currentMode = root.previewMode
            sparkle.restart()
        }
    }

    // When previewMode changes externally (skill edit + restart), sync _currentMode
    onPreviewModeChanged: root._currentMode = root.previewMode
}
