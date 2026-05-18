pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick

/// Individual agent display: sparkle animation (busy) or activity icon.
Item {
    id: root

    required property bool active
    required property string activityState
    required property string activityTool
    required property bool isSttTarget

    property bool _isClosing: false
    property bool _blinkClosing: false // true from the stopping phase of a clear-blink until activityState leaves "clearing"
    property bool _startClosing: false // true from the stopping phase of a start-blink until activityState leaves "starting"
    property bool _sttEmerging: false // true during the starting phase before stt-morph
    property bool _sttWaving: false // true after stt-morph completes → looping wave
    property bool _sttTranscribeMorphing: false // true while playing the one-shot wave→transcribe bridge sprite
    property bool _sttSparkleMorphing: false // true while playing the reverse exit morph (bars → sparkle starburst)
    property bool _keyEmerging: false // true during dot → starburst emerge before key morph
    property bool _keyMorphActive: false // true while key-morph sprite is playing or held at key shape

    // Ask/plan morphs have dedicated icons — suppress the generic key-morph path
    readonly property bool _isSpecialPermission: root.activityTool === "Asking" || root.activityTool === "Planning"

    implicitWidth: sparkle.implicitWidth
    implicitHeight: sparkle.implicitHeight

    readonly property string _sparkleMode: {
        // Ask/plan morphs override key — they're needs_permission variants
        // with distinct icons (? and plan list) instead of the generic key
        if (root.activityTool === "Asking") return "ask-morph";
        if (root.activityTool === "Planning") return "plan-morph";
        // Key permission morph (generic tool approval)
        if (root._keyMorphActive) return "key-morph";
        if (root._keyEmerging) return "starting";
        // STT exit morph: bars → sparkle starburst (reverse playback of
        // stt-morph). Plays after the agent stops being the STT target while
        // the wave was looping, so the chip lands back on the same sparkle
        // frame that working/stopping/starting begin with — seamless handoff
        // to whatever mode follows. Highest priority among STT branches
        // because by this point isSttTarget is already false.
        if (root._sttSparkleMorphing) return "stt-sparkle-morph";
        // STT wave/morph. Once morph completes (_sttWaving), pick the looping
        // wave variant: center-pulse during active recording, left-to-right
        // sweep while the captured audio is processing/transcribing/delivering.
        // AgentService.sttIsTranscribing mirrors the same coalesced phase the
        // recorder widget shows (modules/recorder/RecordingBarEmbed.qml).
        // _sttTranscribeMorphing takes priority over the looping selection:
        // when the recording→transcribing transition is detected (see the
        // Connections block below), this flag plays a one-shot bridge sprite
        // that collapses the wave to a flat baseline and re-emerges into
        // stt-transcribe's first frame, so the eye sees a clean handoff
        // rather than a hot-swap between two unrelated loop phases.
        if (root.isSttTarget) {
            if (root._sttEmerging) return "starting";
            if (root._sttTranscribeMorphing) return "stt-wave-to-transcribe-morph";
            if (root._sttWaving) return AgentService.sttIsTranscribing ? "stt-transcribe" : "stt-wave";
            return "stt-morph";
        }
        if (root._isClosing || root._blinkClosing || root._startClosing)
            return "stopping";
        if (!root.isBusy)
            return "stopping"; // Idle: show dormant dot (last frame of stopping sprite)
        // Busy path
        if (root.activityState === "starting" || root.activityState === "clearing")
            return "starting";
        return "working";
    }

    readonly property bool isBusy: root.activityState === "working" || root.activityState === "thinking"
        || root.activityState === "starting" || root.activityState === "clearing"

    onIsBusyChanged: {
        if (root.isBusy) {
            root._isClosing = false
        } else if (root.activityState === "needs_permission") {
            // Key-morph only for generic permissions — ask/plan morphs handle
            // their own needs_permission variants via _sparkleMode binding
            if (!root._isSpecialPermission) {
                root._keyMorphActive = true
            }
        } else {
            root._isClosing = true
        }
    }

    onIsSttTargetChanged: {
        if (root.isSttTarget && !root.isBusy) {
            // Agent was idle (dormant dot) — emerge first, then morph
            root._sttEmerging = true
        } else if (!root.isSttTarget && root._sttWaving) {
            // Target just cleared while the chip was looping the wave/transcribe.
            // Play the exit morph (reverse stt-morph: bars → sparkle starburst)
            // before the chip falls through to its natural next mode. Lands
            // on the same sparkle frame working/stopping/starting begin with.
            // Clear other in-flight STT flags so the exit morph wins outright.
            root._sttSparkleMorphing = true
            root._sttEmerging = false
            root._sttTranscribeMorphing = false
            // _sttWaving stays true intentionally — it's the marker that we
            // were in a wave state and therefore owe an exit morph. Cleared
            // together with _sttSparkleMorphing on animationComplete.
        } else if (root.isSttTarget) {
            // Becoming the target while already busy — skip the dormant-dot emerge
            // and jump straight to stt-morph. No flags needed; _sparkleMode will
            // return "stt-morph" because isSttTarget is true and _sttWaving is false.
            root._sttEmerging = false
            root._sttWaving = false
            root._sttTranscribeMorphing = false
        } else {
            // Un-targeted while not yet waving (chip was in starting/emerge/morph
            // phase, not the looping wave). No exit morph — just clear STT flags.
            root._sttEmerging = false
            root._sttWaving = false
            root._sttTranscribeMorphing = false
        }
    }

    // Detect the recording→transcribing handoff: when AgentService flips
    // sttIsTranscribing true while we're already in the looping wave state,
    // play the one-shot bridge morph before the looping LTR transcribe takes
    // over. The guard on _sttWaving ensures we only morph from the wave (not
    // mid-emerge or mid-stt-morph — those paths fall directly into the
    // correct looping mode based on sttIsTranscribing at completion time).
    Connections {
        target: AgentService
        function onSttIsTranscribingChanged() {
            if (AgentService.sttIsTranscribing
                && root.isSttTarget
                && root._sttWaving
                && !root._sttTranscribeMorphing
                && !root._sttSparkleMorphing) {
                root._sttTranscribeMorphing = true
            }
        }
    }

    onActivityStateChanged: {
        if (root.activityState !== "clearing") {
            // Reset blink phase when state changes away from clearing
            // (e.g., user submits a prompt → "thinking" while blink is still playing)
            root._blinkClosing = false
        }
        if (root.activityState !== "starting") {
            root._startClosing = false
        }
        // Key morph: entering needs_permission from idle (dormant dot)
        // Only for generic permissions — ask/plan morphs don't need the emerge
        if (root.activityState === "needs_permission" && !root.isBusy && !root._keyMorphActive) {
            if (!root._isSpecialPermission) {
                root._keyEmerging = true
            }
        }
        // Key morph: leaving needs_permission — reset key flags
        if (root.activityState !== "needs_permission") {
            root._keyMorphActive = false
            root._keyEmerging = false
        }
    }

    // ── Claude sparkle (always visible — dormant dot when idle, animates when busy) ──
    ClaudeSparkle {
        id: sparkle
        color: "#d97757" // Claude brand orange — intentionally fixed, not themed
        // 0.6× for STT/key emerge and both clear-blink phases (activityState stays
        // "clearing" through starting AND stopping). stt-morph/stt-wave/key-morph run at 1.0.
        // Total clear-blink: ~545ms + ~1094ms ≈ 1640ms at 0.6×.
        speedFactor: (root._sttEmerging || root._keyEmerging || root.activityState === "clearing" || root._startClosing) ? 0.6 : 1.0
        mode: root._sparkleMode
        // Note: reverse playback for stt-sparkle-morph is derived internally
        // by ClaudeSparkle from mode itself — must NOT be set as an external
        // binding here, or it races with mode and the morph snaps instantly.
        // Handle initial state on creation (no animation — skip to final frame)
        Component.onCompleted: {
            if (root.activityTool === "Asking" || root.activityTool === "Planning") {
                // Already asking or plan presented — show icon directly
                root._keyEmerging = false
                root._keyMorphActive = false
                sparkle.skipToEnd()
            } else if (root.activityState === "needs_permission" && !root.isBusy) {
                // Already in needs_permission — show key shape directly
                root._keyEmerging = false
                root._keyMorphActive = true
                sparkle.skipToEnd()
            } else if (!root.isBusy && !root._isClosing) {
                sparkle.skipToEnd()
            }
        }
        onAnimationComplete: {
            // Key emerge: starting completes → transition to key-morph
            if (root._keyEmerging) {
                root._keyEmerging = false
                root._keyMorphActive = true
            // Key-morph completion: one-shot holds at key shape, no handler needed.
            // STT emerge: starting completes → transition to stt-morph
            } else if (root.isSttTarget && root._sttEmerging) {
                root._sttEmerging = false
            // STT morph: stt-morph one-shot completes → transition to looping stt-wave.
            // (stt-morph is the only mode that satisfies isSttTarget && !_sttWaving here
            // because _sttEmerging is cleared above and stt-wave never fires animationComplete.)
            } else if (root.isSttTarget && !root._sttWaving) {
                root._sttWaving = true
            // Safe: stt-wave is looping (not one-shot) so animationComplete never fires during wave.
            // Wave→transcribe bridge morph completes → drop the flag so
            // _sparkleMode falls through to the looping stt-transcribe.
            // If sttIsTranscribing flipped false mid-morph (rare — would
            // require the STT job to error or complete within ~960ms of
            // the user stopping recording), we land on stt-wave instead.
            // Visually surprising but harmless: the chip almost always
            // unmounts immediately after via clearSttTarget anyway.
            } else if (root.isSttTarget && root._sttTranscribeMorphing) {
                root._sttTranscribeMorphing = false
            // STT exit morph completes — clear all STT flags so _sparkleMode
            // falls through to whatever the agent is now doing (working /
            // stopping / etc.). Lands on the sparkle starburst, which is
            // frame 0 of those modes — visually seamless handoff.
            } else if (root._sttSparkleMorphing) {
                root._sttSparkleMorphing = false
                root._sttWaving = false
            // Start-blink: starting completes during "starting" → transition to stopping
            } else if (root.activityState === "starting" && !root._startClosing) {
                root._startClosing = true
            // Blink: starting completes during "clearing" → transition to stopping
            } else if (root.activityState === "clearing" && !root._blinkClosing) {
                root._blinkClosing = true
            // Stopping animation finished — chip is now at dormant dot.
            // Reset _isClosing so Repeater re-instantiation sees clean state.
            } else if (root._isClosing) {
                root._isClosing = false
            }
            // Note: _blinkClosing is NOT reset here. If the stopping phase of a
            // clear-blink finishes while activityState is still "clearing", resetting
            // _blinkClosing would cause _sparkleMode to fall through to "starting"
            // again, looping the blink indefinitely. Instead, _blinkClosing stays
            // true (keeping mode at "stopping" / dormant dot) until activityState
            // changes away from "clearing" — handled by onActivityStateChanged.
        }
    }

}
