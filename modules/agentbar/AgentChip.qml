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

    spacing: 2
    verticalItemAlignment: Qt.AlignVCenter

    // ── Activity-aware color (shared by number and icon) ──────────────
    readonly property color _activityColor: {
        if (root.activityState === "needs_permission") return Colours.palette.m3error;
        if (root.isBusy) return Colours.palette.m3primary;
        return root.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant;
    }

    readonly property int _fontWeight: (root.active || root.isBusy) ? Font.DemiBold : Font.Normal

    readonly property string _sparkleMode: {
        if (root.isSttTarget)
            return root._sttEmerging ? "starting" : "stt-morph";
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
        } else {
            root._sttEmerging = false
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
    readonly property string _iconText: _activityIcon(root.activityState, root.activityTool)

    function _activityIcon(state: string, tool: string): string {
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
            // Blink: starting completes during "clearing" → transition to stopping
            } else if (root.activityState === "clearing" && !root._blinkClosing) {
                root._blinkClosing = true
            }
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
