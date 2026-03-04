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

    property bool _isClosing: false

    spacing: 2

    // ── Activity-aware color (shared by number and icon) ──────────────
    readonly property color _activityColor: {
        if (root.activityState === "needs_permission") return Colours.palette.m3error;
        if (root.isBusy) return Colours.palette.m3primary;
        return root.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant;
    }

    readonly property int _fontWeight: (root.active || root.isBusy) ? Font.DemiBold : Font.Normal

    readonly property bool isBusy: root.activityState === "working" || root.activityState === "thinking"
        || root.activityState === "starting"

    onIsBusyChanged: {
        if (root.isBusy) {
            root._isClosing = false
        } else if (root.activityState !== "needs_permission") {
            root._isClosing = true
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
        mode: root._isClosing ? "stopping"
            : root.isBusy ? (root.activityState === "thinking" ? "thinking"
                : root.activityState === "starting" ? "starting"
                : "working")
            : "stopping" // Idle: show dormant dot (last frame of stopping sprite)
        // Skip to dormant dot on creation if agent is already idle
        Component.onCompleted: {
            if (!root.isBusy && !root._isClosing) {
                sparkle._currentFrame = sparkle._frameCount - 1
                sparkle._oneShotComplete = true
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

    // ── STT target badge (sound wave icon) ────────────────────────────
    MaterialIcon {
        visible: root.isSttTarget
        width: visible ? implicitWidth : 0
        text: "graphic_eq"
        color: root._activityColor
        font.pointSize: Appearance.font.size.small
        opacity: _sttPulse

        property real _sttPulse: 1.0

        SequentialAnimation on _sttPulse {
            running: root.isSttTarget && !root.isBusy  // sparkle handles busy state
            loops: Animation.Infinite
            onRunningChanged: if (!running) _sttPulse = 1.0
            NumberAnimation { from: 1.0; to: 0.4; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.4; to: 1.0; duration: 600; easing.type: Easing.InOutSine }
        }
    }
}
