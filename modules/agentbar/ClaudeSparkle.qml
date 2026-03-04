pragma ComponentBehavior: Bound

import Quickshell
import qs.components.effects
import qs.config
import QtQuick

/// Claude sparkle: quad-mode sprite-sheet animation.
/// - "working": 8-frame starburst rotation, 810ms cycle (same as claude.ai streaming).
/// - "thinking": 9-frame dot-to-starburst breathing, 909ms cycle (same as claude.ai thinking).
/// - "starting": 9-frame seed-to-full emergence, 909ms one-shot then holds open.
/// - "stopping": 12-frame full-to-dot collapse, 1824ms one-shot then holds at dormant dot.
/// All modes use identical frame-cycling mechanics for consistent hand-drawn feel.
/// Original assets from claude.ai (Anthropic) — used with attribution.
Item {
    id: root

    required property color color
    property bool running: true
    property string mode: "working" // "thinking" | "working" | "starting" | "stopping"
    property real speedFactor: 1.0 // Multiplier for frame interval (< 1 = faster)

    /// Emitted when a one-shot animation (starting/stopping) reaches its final frame.
    signal animationComplete()

    implicitWidth: _size
    implicitHeight: _size

    // ~1.4× font cap-height gives the starburst visual breathing room vs adjacent text
    readonly property real _size: Appearance.font.size.small * 1.4

    clip: true

    property int _currentFrame: 0
    property bool _oneShotComplete: false
    readonly property bool _isOneShot: root.mode === "starting" || root.mode === "stopping"

    readonly property int _frameCount: root.mode === "thinking" || root.mode === "starting" ? 9
        : root.mode === "stopping" ? 12
        : 8

    readonly property string _spriteAsset: root.mode === "thinking"
        ? "claude-sparkle-thinking-sprite"
        : root.mode === "starting" ? "claude-sparkle-starting-sprite"
        : root.mode === "stopping" ? "claude-sparkle-stopping-sprite"
        : "claude-sparkle-sprite"

    onModeChanged: {
        root._currentFrame = 0
        root._oneShotComplete = false
        console.assert(root.mode === "working" || root.mode === "thinking"
            || root.mode === "starting" || root.mode === "stopping",
            `ClaudeSparkle: invalid mode "${root.mode}", expected "working", "thinking", "starting", or "stopping"`)
    }

    /// Jump directly to the final frame of a one-shot animation (used for initial idle state).
    function skipToEnd() {
        root._currentFrame = root._frameCount - 1
        root._oneShotComplete = true
    }

    Image {
        source: Qt.resolvedUrl(`${Quickshell.shellDir}/assets/${root._spriteAsset}.svg`)
        sourceSize.width: root._size
        sourceSize.height: root._size * root._frameCount
        width: root._size
        height: root._size * root._frameCount
        y: -root._currentFrame * root._size

        layer.enabled: true
        layer.effect: Colouriser {
            sourceColor: "black"
            colorizationColor: root.color
        }
    }

    // Single Timer drives all four modes — same 101ms tick, same hand-drawn feel
    Timer {
        running: root.running && root.visible && !root._oneShotComplete
        interval: Math.round((root.mode === "stopping" ? 152 : 101) * root.speedFactor)
        repeat: true
        onTriggered: {
            const next = root._currentFrame + 1
            if (root._isOneShot) {
                if (next >= root._frameCount) {
                    root._currentFrame = root._frameCount - 1
                    root._oneShotComplete = true
                    root.animationComplete()
                } else {
                    root._currentFrame = next
                }
            } else {
                // Working/thinking loop indefinitely
                root._currentFrame = next % root._frameCount
            }
        }
        // Reset to first frame on pause so re-shows start cleanly.
        // Side effect: if agentbar hides mid-animation, it replays from the start.
        onRunningChanged: if (!running && !root._oneShotComplete) root._currentFrame = 0
    }
}
