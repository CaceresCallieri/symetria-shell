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

    /// The iris runs bigger than the knob because it carries no printed scale —
    /// its whole reading comes from blade edges, and those blur together as it
    /// shrinks. It still fits the shared card: the readout is only 21 px tall, so
    /// a 78 px dial leaves 7 px of slack inside the 114 px interior. Verified
    /// against a real-size render; below roughly 70 px the blades stop reading.
    readonly property real dialScale: contentScale * (showingBrightness ? 0.852 : 0.75)

    /// Falls back to the raw value while the Loader swaps dials, so the readout
    /// never blinks through 0 on a metric change. The fallback duplicates
    /// RotaryControl.normalizedValue — keep the two in step if either changes.
    readonly property real displayValue: dial?.animatedValue
        ?? Math.max(0, Math.min(1, currentValue / Math.max(maximumValue, 0.001)))

    // ONE size for every metric. Each metric has a fixed spot on the right edge
    // that you aim at from muscle memory, and a card that changed shape between
    // them would undercut that — brightness used to run wider and taller to give
    // the iris room, and the dial was shrunk to fit here instead. Expressed in
    // the same design units as the dial and scaled by contentScale, so
    // contentScale still resizes the whole OSD.
    readonly property real cardWidthUnits: 212
    readonly property real cardHeightUnits: 254

    implicitWidth: Math.round(cardWidthUnits * contentScale)
    implicitHeight: Math.round(cardHeightUnits * contentScale)

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
        // Synchronous on purpose. The card is one fixed size today so nothing
        // rebuilds this path mid-animation, but it is five segments and the
        // inline build costs nothing — whereas if a metric ever gets its own card
        // size again, an off-thread rebuild lands a frame late and the outline
        // visibly trails the PillCard it wraps.
        asynchronous: false

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
