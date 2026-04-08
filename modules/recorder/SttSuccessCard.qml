import qs.components
import qs.config
import QtQuick

/// Pop-in success indicator for completed STT transcriptions.
/// Shows delivery-method icon (clipboard/inject/submit) with animated
/// pop from modeBtn position (ask mode) or center (fixed mode).
/// Loaded by Content.qml's terminal-state Loader via sourceComponent wrapper.
Item {
    id: root

    required property real containerWidth
    required property real containerHeight
    required property color iconColor
    required property bool injectionDowngraded
    required property string injectionPath
    required property bool injectionSubmitted
    required property bool isAskMode
    required property real modeBtnX
    required property real modeBtnWidth

    implicitWidth: containerWidth
    implicitHeight: containerHeight

    StyledRect {
        id: pill

        anchors.verticalCenter: parent.verticalCenter

        readonly property real targetIconSize: Appearance.font.size.large
        readonly property real targetPadding: Appearance.padding.normal * 2

        implicitWidth: icon.implicitWidth + targetPadding
        implicitHeight: icon.implicitHeight + Appearance.padding.smaller * 2
        width: implicitWidth
        height: implicitHeight

        radius: Appearance.rounding.full
        color: Colours.pillStyle(
            Colours.palette.m3surfaceContainerHigh,
            Colours.glass.subtle
        ).background

        opacity: 0

        MaterialIcon {
            id: icon

            anchors.centerIn: parent
            text: {
                if (root.injectionDowngraded) return "content_copy";
                switch (root.injectionPath) {
                    case "rpc":
                        return root.injectionSubmitted ? "send" : "input";
                    case "paste": return "input";
                    default: return "content_copy";
                }
            }
            color: root.injectionDowngraded
                ? Colours.palette.m3error
                : root.iconColor
            font.pointSize: pill.targetIconSize
        }

        Component.onCompleted: {
            if (root.isAskMode) {
                x = root.modeBtnX + root.modeBtnWidth / 2 - width / 2;
                scale = root.modeBtnWidth / width;
            } else {
                x = (parent.width - width) / 2;
                scale = 0.4;
            }
            popAnim.start();
        }

        ParallelAnimation {
            id: popAnim

            NumberAnimation {
                target: pill
                property: "x"
                to: (pill.parent.width - pill.width) / 2
                duration: Appearance.anim.durations.expressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
            }

            NumberAnimation {
                target: pill
                property: "scale"
                to: 1.0
                duration: Appearance.anim.durations.expressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
            }

            NumberAnimation {
                target: pill
                property: "opacity"
                to: 1.0
                duration: Appearance.anim.durations.small
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
            }
        }
    }
}
