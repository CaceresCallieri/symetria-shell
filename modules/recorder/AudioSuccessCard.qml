import qs.components
import qs.config
import QtQuick

/// Pop-in success indicator for completed audio recordings.
/// Shows an audio_file icon in a pill with scale+fade entrance animation.
/// Loaded by Content.qml's terminal-state Loader via sourceComponent wrapper.
Item {
    id: root

    required property real containerWidth
    required property real containerHeight
    required property color iconColor

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
        color: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle).background

        opacity: 0

        MaterialIcon {
            id: icon

            anchors.centerIn: parent
            text: "audio_file"
            color: root.iconColor
            font.pointSize: pill.targetIconSize
        }

        Component.onCompleted: {
            x = (parent.width - width) / 2;
            scale = 0.4;
            popAnim.start();
        }

        ParallelAnimation {
            id: popAnim

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
