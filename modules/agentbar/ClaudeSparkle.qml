pragma ComponentBehavior: Bound

import Quickshell
import qs.components.effects
import qs.config
import QtQuick

/// Claude sparkle: multi-mode sprite-sheet animation.
/// - "working": 8-frame starburst rotation, 810ms cycle (same as claude.ai streaming).
/// - "working-reverse": the "working" sprite played backwards — an inverted spin.
///   Same sprite/frames/tick; only the loop step flips (see _reverse). Used by the
///   per-turn working-variety roll in AgentChip for visual variety across chips.
/// - "thinking": 9-frame dot-to-starburst breathing, 909ms cycle (same as claude.ai thinking).
/// - "starting": 9-frame seed-to-full emergence, 909ms one-shot then holds open.
/// - "stopping": 12-frame full-to-dot collapse, 1824ms one-shot then holds at dormant dot.
/// - "stt-morph": 12-frame sparkle-to-soundwave morph, one-shot then holds at bars.
/// - "stt-wave": 12-frame looping center-pulse wave (bars ripple outward from center).
/// - "stt-transcribe": 12-frame looping left-to-right traveling wave (used while
///   the captured audio is processing/transcribed/delivering — distinct from the
///   center-pulse stt-wave that plays during active recording).
/// - "stt-wave-to-transcribe-morph": 12-frame one-shot bridge between stt-wave
///   and stt-transcribe. Collapses the bars to a flat baseline (frames 0-5),
///   then re-emerges into stt-transcribe's first frame (frames 6-11) so the
///   eye perceives a "settles down, then a new wave starts" transition rather
///   than a hot-swap between two unrelated loop phases.
/// - "stt-sparkle-morph": exit morph that reuses claude-sparkle-stt-morph-sprite
///   played in REVERSE — soundwave bars collapse back into the Claude sparkle
///   starburst. Lands on frame 0 of stt-morph, which is the same sparkle
///   geometry that working/starting/stopping all begin with, so the handoff
///   to whatever mode follows (working starburst spin, dormant-dot collapse)
///   is visually seamless. No dedicated sprite — leverages stt-morph's
///   existing geometry via reverse playback.
/// - "key-morph": 12-frame sparkle-to-key morph, one-shot then holds at key shape.
/// All modes use identical frame-cycling mechanics for consistent hand-drawn feel.
/// Original assets from claude.ai (Anthropic) — used with attribution.
Item {
    id: root

    required property color color
    property bool running: true
    property string mode: "working" // "thinking" | "working" | "starting" | "stopping" | "stt-morph" | "stt-wave" | "stt-transcribe" | "stt-wave-to-transcribe-morph" | "stt-sparkle-morph" | "key-morph" | "ask-morph" | "plan-morph" | "asking" | "planning"
    property real speedFactor: 1.0 // Multiplier for frame interval (< 1 = faster)
    /// Modes that step the sprite backwards. "stt-sparkle-morph" plays last→0
    /// once (a one-shot exit morph); "working-reverse" loops in reverse (the
    /// inverted starburst spin). Derived from `mode` (not exposed as an external
    /// prop) so that the playback direction updates atomically with `mode` —
    /// otherwise two separate external bindings (mode + reverse) on the same
    /// source race each other and onModeChanged can read a stale reverse value,
    /// leading to the sprite snapping straight to its endpoint instead of animating.
    readonly property bool _reverse: root.mode === "stt-sparkle-morph" || root.mode === "working-reverse"

    /// Per-instance random phase for the looping working/thinking modes, so that
    /// several chips animating at once don't tick in visual lockstep. Two forces
    /// otherwise lock them together: every reset point below seeds _currentFrame
    /// to 0, and Qt's default CoarseTimer coalesces same-interval timers onto
    /// shared wakeup boundaries (a power-saving optimisation) so they also FIRE
    /// together. Seeding each instance's loop at a stable random frame breaks the
    /// *visual* sync without fighting the coalescing — the timers may still tick
    /// in unison, but each chip DISPLAYS a different frame. Opt-in (default
    /// false): one-shot, STT, and preview modes must start at their semantic
    /// frame, so they are excluded via _desyncMode below.
    property bool desyncLoop: false
    // Math.random() has no binding dependencies, so this evaluates exactly once
    // at creation and stays stable for the instance's lifetime.
    readonly property real _loopPhaseFraction: Math.random()
    // Only the looping working-variety modes are desynced; every other mode keeps
    // its exact prior start frame (0 forward, last frame for reverse playback).
    readonly property bool _desyncMode: root.mode === "working" || root.mode === "thinking"
        || root.mode === "working-reverse"
    readonly property int _loopStartFrame: root.desyncLoop && root._desyncMode
        ? Math.floor(root._loopPhaseFraction * root._frameCount)
        : (root._reverse ? root._frameCount - 1 : 0)

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
        || root.mode === "stt-morph" || root.mode === "stt-wave-to-transcribe-morph"
        || root.mode === "stt-sparkle-morph"
        || root.mode === "key-morph"
        || root.mode === "ask-morph" || root.mode === "plan-morph"
    // Modes that use the 80ms tick (vs 101ms default / 152ms stopping).
    readonly property bool _isFastTick: root.mode === "stt-morph" || root.mode === "stt-wave"
        || root.mode === "stt-transcribe" || root.mode === "stt-wave-to-transcribe-morph"
        || root.mode === "stt-sparkle-morph"
        || root.mode === "key-morph"
        || root.mode === "ask-morph" || root.mode === "plan-morph"
    // Modes with 12-frame sprite sheets (vs 9-frame thinking/starting / 8-frame working / 1-frame static).
    readonly property bool _is12Frame: root.mode === "stopping" || root.mode === "stt-morph"
        || root.mode === "stt-wave" || root.mode === "stt-transcribe"
        || root.mode === "stt-wave-to-transcribe-morph"
        || root.mode === "stt-sparkle-morph"
        || root.mode === "key-morph"
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
        : root.mode === "stt-wave-to-transcribe-morph" ? "claude-sparkle-stt-wave-to-transcribe-morph-sprite"
        // Exit morph reuses the sparkle→bars sprite. _reverse (derived from mode)
        // makes the Timer step backward, so frames 11→0 (bars back to sparkle).
        : root.mode === "stt-sparkle-morph" ? "claude-sparkle-stt-morph-sprite"
        : "claude-sparkle-sprite"

    onModeChanged: {
        // _loopStartFrame == the old `_reverse ? last : 0` for every mode except
        // working/thinking with desyncLoop set, where it's a stable random frame.
        root._currentFrame = root._loopStartFrame
        root._oneShotComplete = false
        console.assert(root.mode === "working" || root.mode === "working-reverse" || root.mode === "thinking"
            || root.mode === "starting" || root.mode === "stopping"
            || root.mode === "stt-morph" || root.mode === "stt-wave" || root.mode === "stt-transcribe"
            || root.mode === "stt-wave-to-transcribe-morph" || root.mode === "stt-sparkle-morph"
            || root.mode === "key-morph" || root.mode === "ask-morph" || root.mode === "plan-morph"
            || root.mode === "asking" || root.mode === "planning",
            `ClaudeSparkle: invalid mode "${root.mode}", expected "working", "working-reverse", "thinking", "starting", "stopping", "stt-morph", "stt-wave", "stt-transcribe", "stt-wave-to-transcribe-morph", "stt-sparkle-morph", "key-morph", "ask-morph", "plan-morph", "asking", or "planning"`)
    }

    // Seed the random loop phase at construction too: a chip born already-busy
    // (e.g. shell restart mid-task) keeps mode == "working" from the default, so
    // onModeChanged never fires and _currentFrame would otherwise sit at 0 until
    // the first reset. Guarded to _desyncMode, so it can't clobber the idle
    // skipToEnd() path (idle modes aren't working/thinking).
    Component.onCompleted: if (root.desyncLoop && root._desyncMode) root._currentFrame = root._loopStartFrame

    /// Jump directly to the final frame of a one-shot animation (used for initial idle state).
    function skipToEnd() {
        root._currentFrame = root._frameCount - 1
        root._oneShotComplete = true
    }

    /// Restart the current animation from its start frame (frame 0 for forward modes, last frame
    /// for reverse modes). Useful for looping one-shot previews in SpritePreview.qml.
    function restart() {
        root._currentFrame = root._reverse ? root._frameCount - 1 : 0
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
            const step = root._reverse ? -1 : 1
            const next = root._currentFrame + step
            if (root._isOneShot) {
                // Done when we step past either end: forward overflows _frameCount,
                // reverse underflows below 0. Hold at the terminal frame (last for
                // forward, first for reverse — which is the landing baseline shape).
                const overshot = root._reverse ? next < 0 : next >= root._frameCount
                if (overshot) {
                    root._currentFrame = root._reverse ? 0 : root._frameCount - 1
                    root._oneShotComplete = true
                    root.animationComplete()
                } else {
                    root._currentFrame = next
                }
            } else {
                // Looping modes (working/thinking/stt-wave/stt-transcribe): wrap
                // via modulo. reverse + looping is supported by the same arithmetic
                // because (-1 % N) in JS returns -1, so we add N before %.
                root._currentFrame = (next + root._frameCount) % root._frameCount
            }
        }
        // Reset to start position on pause so re-shows begin cleanly. For reverse modes,
        // "start" is the last frame (they play last→0); for desynced working/thinking
        // it's this instance's stable random frame (so a shared hide/show — the most
        // common sync trigger — re-seeds each chip to its OWN phase, not all to 0).
        // Side effect: if agentbar hides mid-animation (including stt-wave loop or
        // stt-sparkle-morph), it replays from the beginning on next show.
        onRunningChanged: if (!running && !root._oneShotComplete) root._currentFrame = root._loopStartFrame
    }
}
