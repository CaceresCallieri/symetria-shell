pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick

/// Individual agent display: instance number with activity-aware coloring and pulse.
StyledText {
    id: root

    required property int instanceNum
    required property bool active
    required property string activityState

    text: root.instanceNum

    color: {
        if (root.activityState === "needs_permission") return Colours.palette.m3error;
        if (root.activityState === "working" || root.activityState === "thinking")
            return Colours.palette.m3primary;
        return root.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant;
    }

    font.weight: (root.active || root.activityState === "working" || root.activityState === "thinking")
        ? Font.DemiBold : Font.Normal
    font.pointSize: Appearance.font.size.small

    // Pulse opacity when busy (thinking or working)
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
}
