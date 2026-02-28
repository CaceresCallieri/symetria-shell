pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick

/// Individual agent display: instance number + activity icon with coloring and pulse.
Row {
    id: root

    required property int instanceNum
    required property bool active
    required property string activityState
    required property string activityTool

    spacing: 2

    // ── Activity-aware color (shared by number and icon) ──────────────
    readonly property color _activityColor: {
        if (root.activityState === "needs_permission") return Colours.palette.m3error;
        if (root.activityState === "working" || root.activityState === "thinking")
            return Colours.palette.m3primary;
        return root.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant;
    }

    readonly property int _fontWeight: (root.active || root.activityState === "working"
        || root.activityState === "thinking") ? Font.DemiBold : Font.Normal

    // ── Pulse animation (on Row → both number and icon pulse together) ──
    readonly property bool isBusy: root.activityState === "working" || root.activityState === "thinking"
    opacity: isBusy ? _pulseValue : 1.0
    property real _pulseValue: 1.0

    SequentialAnimation on _pulseValue {
        running: root.isBusy
        loops: Animation.Infinite
        onRunningChanged: if (!running) _pulseValue = 1.0
        NumberAnimation { from: 1.0; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.35; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
    }

    // ── Icon mapping ─────────────────────────────────────────────────
    readonly property string _iconText: _activityIcon(root.activityState, root.activityTool)

    function _activityIcon(state: string, tool: string): string {
        switch (state) {
            case "thinking":         return "psychology";
            case "needs_permission": return "lock";
            case "starting":         return "play_arrow";
            case "working":
                switch (tool) {
                    case "Editing":    return "edit";
                    case "Writing":    return "edit";
                    case "Reading":    return "visibility";
                    case "Running":    return "terminal";
                    case "Searching":  return "search";
                    case "Fetching":   return "language";
                    case "Delegating": return "fork_right";
                    case "Planning":   return "map";
                    case "Asking":     return "chat_bubble";
                    case "Organizing": return "checklist";
                    default:           return "construction";
                }
            default: return "";
        }
    }

    // ── Instance number ──────────────────────────────────────────────
    StyledText {
        text: root.instanceNum
        color: root._activityColor
        font.weight: root._fontWeight
        font.pointSize: Appearance.font.size.small
    }

    // ── Activity state icon ──────────────────────────────────────────
    MaterialIcon {
        visible: root._iconText !== ""
        width: visible ? implicitWidth : 0
        text: root._iconText
        color: root._activityColor
        font.pointSize: Appearance.font.size.small
        fill: root.activityState === "needs_permission" ? 1 : 0
    }
}
