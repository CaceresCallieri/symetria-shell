pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import QtQuick
import QtQuick.Shapes

Item {
    id: root

    required property Brightness.Monitor monitor
    required property string activeMetric
    required property real volume
    required property bool muted
    required property real sourceVolume
    required property bool sourceMuted
    required property real brightness

    readonly property bool interacting: knob.interacting
    readonly property real currentValue: activeMetric === "brightness"
        ? brightness
        : activeMetric === "microphone" ? sourceVolume : volume
    readonly property real maximumValue: activeMetric === "brightness" ? 1 : Config.services.maxVolume
    readonly property real contentScale: 0.52
    readonly property real attachmentCurve: Math.min(Config.border.rounding, height / 2)
    readonly property real surroundWidth: Appearance.padding.large
    readonly property color surroundColor: Qt.alpha(
        Colours.palette.m3surfaceContainer,
        Appearance.transparency.base
    )

    implicitWidth: Math.round(212 * contentScale)
    implicitHeight: 132

    function increment(): void {
        if (activeMetric === "brightness")
            monitor?.setBrightness(brightness + Config.services.brightnessIncrement);
        else if (activeMetric === "microphone")
            Audio.incrementSourceVolume();
        else
            Audio.incrementVolume();
    }

    function decrement(): void {
        if (activeMetric === "brightness")
            monitor?.setBrightness(brightness - Config.services.brightnessIncrement);
        else if (activeMetric === "microphone")
            Audio.decrementSourceVolume();
        else
            Audio.decrementVolume();
    }

    function setValue(value: real): void {
        if (activeMetric === "brightness")
            monitor?.setBrightness(value);
        else if (activeMetric === "microphone")
            Audio.setSourceVolume(value);
        else
            Audio.setVolume(value);
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        asynchronous: true

        ShapePath {
            startX: root.width
            startY: 0
            strokeWidth: 1
            strokeColor: Qt.alpha(Colours.palette.m3outline, 0.14)
            fillColor: root.surroundColor

            PathLine {
                relativeX: -(root.width - root.attachmentCurve)
                relativeY: 0
            }
            PathArc {
                relativeX: -root.attachmentCurve
                relativeY: root.attachmentCurve
                radiusX: root.attachmentCurve
                radiusY: root.attachmentCurve
                direction: PathArc.Counterclockwise
            }
            PathLine {
                relativeX: 0
                relativeY: root.height - root.attachmentCurve * 2
            }
            PathArc {
                relativeX: root.attachmentCurve
                relativeY: root.attachmentCurve
                radiusX: root.attachmentCurve
                radiusY: root.attachmentCurve
                direction: PathArc.Counterclockwise
            }
            PathLine {
                relativeX: root.width - root.attachmentCurve
                relativeY: 0
            }
        }
    }

    PillCard {
        anchors.fill: parent
        anchors.margins: root.surroundWidth
    }

    CustomMouseArea {
        anchors.fill: parent

        function onWheel(event: WheelEvent) {
            if (event.angleDelta.y > 0)
                root.increment();
            else if (event.angleDelta.y < 0)
                root.decrement();
        }

        Column {
            anchors.centerIn: parent
            spacing: Appearance.spacing.normal

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Math.round(knob.animatedValue * root.maximumValue * 100)
                color: Colours.palette.m3onSurface
                font.family: Appearance.font.family.mono
                font.pointSize: Appearance.font.size.extraLarge * root.contentScale
                font.weight: Font.Medium
            }

            RotaryKnob {
                id: knob

                anchors.horizontalCenter: parent.horizontalCenter
                sizeScale: root.contentScale * 0.75
                value: root.currentValue
                to: root.maximumValue
                onMoved: value => root.setValue(value)
                onWheelMoved: delta => {
                    if (delta > 0)
                        root.increment();
                    else if (delta < 0)
                        root.decrement();
                }
            }
        }
    }
}
