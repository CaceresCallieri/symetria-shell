pragma ComponentBehavior: Bound

import Quickshell
import qs.components.effects
import qs.config
import QtQuick

/// Claude sparkle: multi-mode sprite-sheet animation.
/// - "working": 8-frame starburst rotation, 810ms cycle (same as claude.ai streaming).
/// - "thinking": 9-frame dot-to-starburst breathing, 909ms cycle (same as claude.ai thinking).
/// - "starting": 9-frame seed-to-full emergence, 909ms one-shot then holds open.
/// - "stopping": 12-frame full-to-dot collapse, 1824ms one-shot then holds at dormant dot.
/// - "stt-morph": 12-frame sparkle-to-soundwave morph, one-shot then holds at bars.
/// - "stt-wave": 12-frame looping center-pulse wave (bars ripple outward from center).
/// - "stt-transcribe": 12-frame looping left-to-right traveling wave (used while
///   the captured audio is processing/transcribed/delivering — distinct from the
///   center-pulse stt-wave that plays during active recording).
/// - "key-morph": 12-frame sparkle-to-key morph, one-shot then holds at key shape.
/// All modes use identical frame-cycling mechanics for consistent hand-drawn feel.
/// Original assets from claude.ai (Anthropic) — used with attribution.
Item {
    id: root

    required property color color
    property bool running: true
    property string mode: "working" // "thinking" | "working" | "starting" | "stopping" | "stt-morph" | "stt-wave" | "stt-transcribe" | "key-morph" | "ask-morph" | "plan-morph" | "asking" | "planning"
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
    // Modes that play once and hold at the final frame (looping modes omitted).
    // stt-wave and stt-transcribe intentionally omitted — they loop like working/thinking.
    readonly property bool _isOneShot: root.mode === "starting" || root.mode === "stopping"
        || root.mode === "stt-morph" || root.mode === "key-morph"
        || root.mode === "ask-morph" || root.mode === "plan-morph"
    // Modes that use the 80ms tick (vs 101ms default / 152ms stopping).
    readonly property bool _isFastTick: root.mode === "stt-morph" || root.mode === "stt-wave"
        || root.mode === "stt-transcribe" || root.mode === "key-morph"
        || root.mode === "ask-morph" || root.mode === "plan-morph"
    // Modes with 12-frame sprite sheets (vs 9-frame thinking/starting / 8-frame working / 1-frame static).
    readonly property bool _is12Frame: root.mode === "stopping" || root.mode === "stt-morph"
        || root.mode === "stt-wave" || root.mode === "stt-transcribe" || root.mode === "key-morph"
        || root.mode === "ask-morph" || root.mode === "plan-morph"

    readonly property int _frameCount: root.mode === "asking" || root.mode === "planning" ? 1
        : root.mode === "thinking" || root.mode === "starting" ? 9
        : root._is12Frame ? 12
        : 8

    readonly property string _spriteAsset: root.mode === "asking"
        ? "ask-question-icon"
        : root.mode === "planning" ? "plan-list-icon"
        : root.mode === "ask-morph" ? "claude-sparkle-ask-morph-sprite"
        : root.mode === "plan-morph" ? "claude-sparkle-plan-morph-sprite"
        : root.mode === "thinking" ? "claude-sparkle-thinking-sprite"
        : root.mode === "starting" ? "claude-sparkle-starting-sprite"
        : root.mode === "stopping" ? "claude-sparkle-stopping-sprite"
        : root.mode === "stt-morph" ? "claude-sparkle-stt-morph-sprite"
        : root.mode === "key-morph" ? "claude-sparkle-key-morph-sprite"
        : root.mode === "stt-wave" ? "claude-sparkle-stt-wave-2-sprite"
        : root.mode === "stt-transcribe" ? "claude-sparkle-stt-transcribe-sprite"
        : "claude-sparkle-sprite"

    onModeChanged: {
        root._currentFrame = 0
        root._oneShotComplete = false
        console.assert(root.mode === "working" || root.mode === "thinking"
            || root.mode === "starting" || root.mode === "stopping"
            || root.mode === "stt-morph" || root.mode === "stt-wave" || root.mode === "stt-transcribe"
            || root.mode === "key-morph" || root.mode === "ask-morph" || root.mode === "plan-morph"
            || root.mode === "asking" || root.mode === "planning",
            `ClaudeSparkle: invalid mode "${root.mode}", expected "working", "thinking", "starting", "stopping", "stt-morph", "stt-wave", "stt-transcribe", "key-morph", "ask-morph", "plan-morph", "asking", or "planning"`)
    }

    /// Jump directly to the final frame of a one-shot animation (used for initial idle state).
    function skipToEnd() {
        root._currentFrame = root._frameCount - 1
        root._oneShotComplete = true
    }

    /// Restart the current animation from frame 0 (useful for looping one-shot previews).
    function restart() {
        root._currentFrame = 0
        root._oneShotComplete = false
    }

    Image {
        source: Qt.resolvedUrl(`${Quickshell.shellDir}/assets/${root._spriteAsset}.svg`)
        sourceSize.width: root._size
        sourceSize.height: root._size * root._frameCount
        width: root._size
        height: root._size * root._frameCount
        y: -root._currentFrame * root._size

        layer.enabled: root.visible
        layer.effect: Colouriser {
            sourceColor: "black"
            colorizationColor: root.color
        }
    }

    // Single Timer drives all four modes — same 101ms tick, same hand-drawn feel
    Timer {
        running: root.running && root.visible && !root._oneShotComplete
        interval: Math.round((root.mode === "stopping" ? 152
            : root._isFastTick ? 80
            : 101) * root.speedFactor)
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
        // Side effect: if agentbar hides mid-animation (including stt-wave loop), it replays from frame 0 on next show.
        onRunningChanged: if (!running && !root._oneShotComplete) root._currentFrame = 0
    }
}
