pragma ComponentBehavior: Bound

import Quickshell
import qs.components.effects
import qs.config
import QtQuick

/// Claude sparkle: quad-mode sprite-sheet animation.
/// - "working": 8-frame starburst rotation, 810ms cycle (same as claude.ai streaming).
/// - "thinking": 9-frame dot-to-starburst breathing, 909ms cycle (same as claude.ai thinking).
/// - "starting": 15-frame seed-to-full emergence + breathing pulse, 1515ms one-shot then holds open.
/// - "stopping": 12-frame full-to-dot collapse, 1212ms one-shot then holds at dormant dot.
/// All modes use identical frame-cycling mechanics for consistent hand-drawn feel.
/// Original assets from claude.ai (Anthropic) — used with attribution.
Item {
    id: root

    required property color color
    property bool running: true
    property string mode: "working" // "thinking" | "working" | "starting" | "stopping"

    implicitWidth: _size
    implicitHeight: _size

    // ~1.4× font cap-height gives the starburst visual breathing room vs adjacent text
    readonly property real _size: Appearance.font.size.small * 1.4

    clip: true

    property int _currentFrame: 0
    property bool _oneShotComplete: false
    readonly property bool _isOneShot: root.mode === "starting" || root.mode === "stopping"

    readonly property int _frameCount: root.mode === "thinking" ? 9
        : root.mode === "starting" ? 15
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
        interval: root.mode === "stopping" ? 152 : 101
        repeat: true
        onTriggered: {
            const next = root._currentFrame + 1
            if (root._isOneShot) {
                if (next >= root._frameCount) {
                    root._currentFrame = root._frameCount - 1
                    root._oneShotComplete = true
                } else {
                    root._currentFrame = next
                }
            } else {
                // Working/thinking loop indefinitely
                root._currentFrame = next % root._frameCount
            }
        }
        onRunningChanged: if (!running && !root._oneShotComplete) root._currentFrame = 0
    }
}
