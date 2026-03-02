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

    spacing: (root.isBusy || root._iconText !== "" || root.isSttTarget) ? 2 : 0

    // ── Activity-aware color (shared by number and icon) ──────────────
    readonly property color _activityColor: {
        if (root.activityState === "needs_permission") return Colours.palette.m3error;
        if (root.activityState === "working" || root.activityState === "thinking")
            return Colours.palette.m3primary;
        return root.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant;
    }

    readonly property int _fontWeight: (root.active || root.activityState === "working"
        || root.activityState === "thinking") ? Font.DemiBold : Font.Normal

    readonly property bool isBusy: root.activityState === "working" || root.activityState === "thinking"

    // ── Icon mapping ─────────────────────────────────────────────────
    readonly property string _iconText: _activityIcon(root.activityState, root.activityTool)

    function _activityIcon(state: string, tool: string): string {
        switch (state) {
            case "needs_permission": return "lock";
            case "starting":         return "play_arrow";
            case "working":
            case "thinking":         return "";
            default:                 return "";
        }
    }

    // ── Instance number ──────────────────────────────────────────────
    StyledText {
        text: root.instanceNum
        color: root._activityColor
        font.weight: root._fontWeight
        font.pointSize: Appearance.font.size.small
    }

    // ── Claude sparkle (replaces icon when busy) ─────────────────────
    ClaudeSparkle {
        visible: root.isBusy
        width: visible ? implicitWidth : 0
        color: "#d97757" // Claude brand orange — intentionally fixed, not themed
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
