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
    /// Whether the OSD is on its way in or already showing. The iris uses it to
    /// sweep open on arrival and snap shut on the way out.
    required property bool revealed

    readonly property bool showingBrightness: activeMetric === "brightness"
    readonly property var dial: dialLoader.item
    readonly property bool interacting: dial?.interacting ?? false
    readonly property real currentValue: showingBrightness
        ? brightness
        : activeMetric === "microphone" ? sourceVolume : volume
    readonly property bool activeMuted: activeMetric === "microphone"
        ? sourceMuted
        : activeMetric === "volume" && muted
    readonly property real maximumValue: showingBrightness ? 1 : Config.services.maxVolume
    readonly property real contentScale: 0.52
    readonly property real attachmentCurve: Math.min(Config.border.rounding, height / 2)
    readonly property real surroundWidth: Appearance.padding.large
    readonly property color surroundColor: Qt.alpha(
        Colours.palette.m3surfaceContainer,
        Appearance.transparency.base
    )

    /// The iris needs more diameter than the knob does: it carries no printed
    /// scale, so its whole reading comes from blade edges that blur together
    /// below roughly 80 px. The card grows with it rather than the dial being
    /// squeezed to fit — verified against a real-size render before porting.
    readonly property real dialScale: contentScale * (showingBrightness ? 0.92 : 0.75)

    /// Falls back to the raw value while the Loader swaps dials, so the readout
    /// never blinks through 0 on a metric change.
    readonly property real displayValue: dial?.animatedValue
        ?? Math.max(0, Math.min(1, currentValue / Math.max(maximumValue, 0.001)))

    implicitWidth: showingBrightness ? 120 : Math.round(212 * contentScale)
    implicitHeight: showingBrightness ? 152 : 132

    // A metric can change while the OSD is already on screen (volume, then
    // brightness, inside the hide delay). Without these the card would snap to
    // the new size mid-show.
    Behavior on implicitWidth {
        Anim {}
    }

    Behavior on implicitHeight {
        Anim {}
    }

    /// Single place that turns a wheel delta into a step, shared by the card and
    /// by whichever dial is loaded.
    function scrollBy(delta: real): void {
        if (delta > 0)
            increment();
        else if (delta < 0)
            decrement();
    }

    function increment(): void {
        if (showingBrightness)
            monitor?.setBrightness(brightness + Config.services.brightnessIncrement);
        else if (activeMetric === "microphone")
            Audio.incrementSourceVolume();
        else
            Audio.incrementVolume();
    }

    function decrement(): void {
        if (showingBrightness)
            monitor?.setBrightness(brightness - Config.services.brightnessIncrement);
        else if (activeMetric === "microphone")
            Audio.decrementSourceVolume();
        else
            Audio.decrementVolume();
    }

    function setValue(value: real): void {
        if (showingBrightness)
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

        function onWheel(event: WheelEvent): void {
            root.scrollBy(event.angleDelta.y);
        }

        Column {
            anchors.centerIn: parent
            spacing: Appearance.spacing.normal
            opacity: root.activeMuted ? 0.38 : 1

            Behavior on opacity {
                Anim {
                    duration: Appearance.anim.durations.small
                }
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Math.round(root.displayValue * root.maximumValue * 100)
                color: Colours.palette.m3onSurface
                font.family: Appearance.font.family.mono
                font.pointSize: Appearance.font.size.extraLarge * root.contentScale
                font.weight: Font.Medium
            }

            // Brightness and volume are different mechanisms, not one dial with a
            // different label, so the visual is swapped rather than reskinned.
            // Both sides derive from RotaryControl, which is what keeps the drag
            // and wheel behaviour identical between them.
            Loader {
                id: dialLoader

                anchors.horizontalCenter: parent.horizontalCenter
                sourceComponent: root.showingBrightness ? irisDial : knobDial
            }
        }
    }

    Component {
        id: knobDial

        RotaryKnob {
            sizeScale: root.dialScale
            value: root.currentValue
            to: root.maximumValue
            onMoved: value => root.setValue(value)
            onWheelMoved: delta => root.scrollBy(delta)
        }
    }

    Component {
        id: irisDial

        BrightnessIris {
            sizeScale: root.dialScale
            value: root.currentValue
            to: root.maximumValue
            revealed: root.revealed
            onMoved: value => root.setValue(value)
            onWheelMoved: delta => root.scrollBy(delta)
        }
    }
}
