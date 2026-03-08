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
    required property bool inPlanMode

    property bool _isClosing: false
    property bool _blinkClosing: false // true from the stopping phase of a clear-blink until activityState leaves "clearing"
    property bool _sttEmerging: false // true during the starting phase before stt-morph
    property bool _sttWaving: false // true after stt-morph completes → looping wave
    property bool _keyEmerging: false // true during dot → starburst emerge before key morph
    property bool _keyMorphActive: false // true while key-morph sprite is playing or held at key shape

    implicitWidth: sparkle.implicitWidth
    implicitHeight: sparkle.implicitHeight

    readonly property string _sparkleMode: {
        // Key permission morph takes visual priority
        if (root._keyMorphActive) return "key-morph";
        if (root._keyEmerging) return "starting";
        // STT wave/morph
        if (root.isSttTarget) {
            if (root._sttEmerging) return "starting";
            if (root._sttWaving) return "stt-wave";
            return "stt-morph";
        }
        if (root._isClosing || root._blinkClosing)
            return "stopping";
        if (!root.isBusy)
            return "stopping"; // Idle: show dormant dot (last frame of stopping sprite)
        // Busy path
        if (root.activityState === "starting" || root.activityState === "clearing")
            return "starting";
        return root.inPlanMode ? "thinking" : "working";
    }

    readonly property bool isBusy: root.activityState === "working" || root.activityState === "thinking"
        || root.activityState === "starting" || root.activityState === "clearing"

    onIsBusyChanged: {
        if (root.isBusy) {
            root._isClosing = false
        } else if (root.activityState === "needs_permission") {
            // Busy → needs_permission: starburst is already showing, morph directly to key
            root._keyMorphActive = true
        } else {
            root._isClosing = true
        }
    }

    onIsSttTargetChanged: {
        if (root.isSttTarget && !root.isBusy) {
            // Agent was idle (dormant dot) — emerge first, then morph
            root._sttEmerging = true
        } else {
            // Either busy (jump directly to stt-morph — no emerge needed
            // from active starburst) or un-targeted — clear both flags.
            root._sttEmerging = false
            root._sttWaving = false
        }
    }

    onActivityStateChanged: {
        if (root.activityState !== "clearing") {
            // Reset blink phase when state changes away from clearing
            // (e.g., user submits a prompt → "thinking" while blink is still playing)
            root._blinkClosing = false
        }
        // Key morph: entering needs_permission from idle (dormant dot)
        if (root.activityState === "needs_permission" && !root.isBusy && !root._keyMorphActive) {
            root._keyEmerging = true
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
        speedFactor: (root._sttEmerging || root._keyEmerging || root.activityState === "clearing") ? 0.6 : 1.0
        mode: root._sparkleMode
        // Handle initial state on creation (no animation — skip to final frame)
        Component.onCompleted: {
            if (root.activityState === "needs_permission" && !root.isBusy) {
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
            // STT morph: morph completes → transition to looping stt-wave
            } else if (root.isSttTarget && !root._sttWaving) {
                root._sttWaving = true
            // Safe: stt-wave is looping (not one-shot) so animationComplete never fires during wave.
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
