pragma ComponentBehavior: Bound

import Quickshell
import qs.components.effects
import qs.config
import QtQuick

/// Claude sparkle: dual-mode sprite-sheet animation.
/// - "working": 8-frame starburst sprite sheet, 810ms cycle (same as claude.ai streaming).
/// - "thinking": 9-frame dot-to-starburst breathing sprite sheet, 909ms cycle (same as claude.ai thinking).
/// Both modes use identical frame-cycling mechanics for consistent hand-drawn feel.
/// Original assets from claude.ai (Anthropic) — used with attribution.
Item {
    id: root

    required property color color
    property bool running: true
    property string mode: "working" // "thinking" | "working"

    implicitWidth: _size
    implicitHeight: _size

    // ~1.4× font cap-height gives the starburst visual breathing room vs adjacent text
    readonly property real _size: Appearance.font.size.small * 1.4

    clip: true

    property int _currentFrame: 0

    readonly property int _frameCount: root.mode === "thinking" ? 9 : 8
    onModeChanged: {
        root._currentFrame = 0
        console.assert(root.mode === "working" || root.mode === "thinking",
            `ClaudeSparkle: invalid mode "${root.mode}", expected "working" or "thinking"`)
    }

    Image {
        source: Qt.resolvedUrl(`${Quickshell.shellDir}/assets/${root.mode === "thinking" ? "claude-sparkle-thinking-sprite" : "claude-sparkle-sprite"}.svg`)
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

    // Single Timer drives both modes — same 101ms tick, same hand-drawn feel
    Timer {
        running: root.running && root.visible
        interval: 101
        repeat: true
        onTriggered: root._currentFrame = (root._currentFrame + 1) % root._frameCount
        onRunningChanged: if (!running) root._currentFrame = 0
    }
}
