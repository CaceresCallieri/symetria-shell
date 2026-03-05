pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick

/// Individual agent display: instance number + sparkle animation (busy) or activity icon.
Row {
    id: root

    required property int instanceNum
    required property bool active
    required property string activityState
    required property string activityTool
    required property bool isSttTarget
    required property bool inPlanMode

    property bool _isClosing: false
    property bool _blinkClosing: false // true during the stopping phase of a clear-blink
    property bool _sttEmerging: false // true during the starting phase before stt-morph
    property bool _sttWaving: false // true after stt-morph completes → looping wave

    spacing: 2

    // ── Activity-aware color (shared by number and icon) ──────────────
    readonly property color _activityColor: {
        if (root.activityState === "needs_permission") return Colours.palette.m3error;
        if (root.isBusy) return Colours.palette.m3primary;
        return root.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant;
    }

    readonly property int _fontWeight: (root.active || root.isBusy) ? Font.DemiBold : Font.Normal

    readonly property string _sparkleMode: {
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
        } else if (root.activityState !== "needs_permission") {
            // Only collapse when going idle — needs_permission shows lock icon instead
            root._isClosing = true
        }
    }

    onIsSttTargetChanged: {
        if (root.isSttTarget && !root.isBusy) {
            // Agent was idle (dormant dot) — emerge first, then morph
            root._sttEmerging = true
        } else if (root.isSttTarget && root.isBusy) {
            // Agent is busy (already animating) — jump directly to stt-morph
            // via _sparkleMode binding (no emerge needed from active starburst)
            root._sttEmerging = false
            root._sttWaving = false
        } else {
            root._sttEmerging = false
            root._sttWaving = false
        }
    }

    onActivityStateChanged: {
        if (root.activityState !== "clearing") {
            // Reset blink phase when state changes away from clearing
            // (e.g., user submits a prompt → "thinking" while blink is still playing)
            root._blinkClosing = false
        } else if (root._blinkClosing) {
            // Rapid-fire /clear: restart the blink by resetting the stopping phase.
            root._blinkClosing = false
        }
    }

    // ── Icon mapping ─────────────────────────────────────────────────
    readonly property string _iconText: _activityIcon(root.activityState)

    function _activityIcon(state: string): string {
        switch (state) {
            case "needs_permission": return "lock";
            default:                 return ""; // working/thinking/starting handled by ClaudeSparkle
        }
    }

    // ── Instance number ──────────────────────────────────────────────
    StyledText {
        text: root.instanceNum
        color: root._activityColor
        font.weight: root._fontWeight
        font.pointSize: Appearance.font.size.small
    }

    // ── Claude sparkle (always visible — dormant dot when idle, animates when busy) ──
    ClaudeSparkle {
        id: sparkle
        color: "#d97757" // Claude brand orange — intentionally fixed, not themed
        // 0.6× applies to both blink phases — activityState stays "clearing" through
        // starting AND stopping. Total blink: ~545ms + ~1094ms ≈ 1640ms.
        speedFactor: (root._sttEmerging || root.activityState === "clearing") ? 0.6 : 1.0
        mode: root._sparkleMode
        // Skip to dormant dot on creation if agent is already idle
        Component.onCompleted: {
            if (!root.isBusy && !root._isClosing) sparkle.skipToEnd()
        }
        onAnimationComplete: {
            // STT emerge: starting completes → transition to stt-morph
            if (root.isSttTarget && root._sttEmerging) {
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

    // ── Activity state icon (non-busy states only) ──────────────────
    MaterialIcon {
        visible: !root.isBusy && root._iconText !== ""
        width: visible ? implicitWidth : 0
        text: root._iconText
        color: root._activityColor
        font.pointSize: Appearance.font.size.small
        fill: root.activityState === "needs_permission" ? 1 : 0
    }

}
