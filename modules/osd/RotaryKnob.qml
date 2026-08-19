pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import QtQuick

Item {
    id: root

    required property real value
    required property real to
    property bool interactive: true
    property real sizeScale: 1

    signal moved(real value)
    signal wheelMoved(real delta)

    readonly property real normalizedValue: Math.max(0, Math.min(1, value / Math.max(to, 0.001)))
    readonly property bool interacting: interaction.pressed || wheelInteractionTimer.running
    property real animatedValue: normalizedValue

    implicitWidth: Math.round(176 * sizeScale)
    implicitHeight: Math.round(176 * sizeScale)

    Behavior on animatedValue {
        Anim {
            duration: Appearance.anim.durations.expressiveFastSpatial
            easing.bezierCurve: Appearance.anim.curves.expressiveEffects
        }
    }

    Item {
        id: tickRing

        anchors.fill: parent

        Repeater {
            model: 51

            delegate: Item {
                id: tick

                required property int index

                width: tickRing.width
                height: tickRing.height
                anchors.centerIn: tickRing
                rotation: -135 + index * 5.4

                Rectangle {
                    width: tick.index % 5 === 0 ? Math.max(2, 2.5 * root.sizeScale) : 1
                    height: tick.index % 5 === 0 ? Math.round(14 * root.sizeScale) : Math.round(8 * root.sizeScale)
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: width / 2
                    color: tick.index / 50 <= root.animatedValue
                        ? Colours.palette.m3onSurface
                        : Qt.alpha(Colours.palette.m3onSurfaceVariant, 0.22)
                }
            }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.round(128 * root.sizeScale)
        height: width
        radius: width / 2
        color: Qt.rgba(0.015, 0.018, 0.022, 0.94)
        border.width: Math.max(1, 2 * root.sizeScale)
        border.color: Qt.rgba(0.42, 0.45, 0.48, 0.32)
    }

    PillSurface {
        id: knobBody

        anchors.centerIn: parent
        width: Math.round(116 * root.sizeScale)
        height: width
        radius: width / 2
        color: Qt.rgba(0.48, 0.50, 0.52, 1)
        borderWidth: Math.max(1, 2 * root.sizeScale)
        borderColor: Qt.rgba(0.82, 0.84, 0.85, 0.9)
        finishRecipe: Theme.engaged

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.00; color: Qt.rgba(0.05, 0.06, 0.07, 0.34) }
                GradientStop { position: 0.28; color: Qt.rgba(1, 1, 1, 0.34) }
                GradientStop { position: 0.52; color: Qt.rgba(1, 1, 1, 0.06) }
                GradientStop { position: 0.76; color: Qt.rgba(0.03, 0.04, 0.05, 0.30) }
                GradientStop { position: 1.00; color: Qt.rgba(1, 1, 1, 0.16) }
            }
        }

        Item {
            anchors.fill: parent
            rotation: -135 + root.animatedValue * 270

            Rectangle {
                width: Math.max(5, 9 * root.sizeScale)
                height: width
                anchors.top: parent.top
                anchors.topMargin: Math.round(14 * root.sizeScale)
                anchors.horizontalCenter: parent.horizontalCenter
                radius: width / 2
                color: Qt.rgba(0.035, 0.045, 0.055, 1)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.46)
            }
        }
    }

    CustomMouseArea {
        id: interaction

        anchors.fill: knobBody
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor

        function onWheel(event: WheelEvent): void {
            wheelInteractionTimer.restart();
            root.wheelMoved(event.angleDelta.y);
        }

        function updateValue(x: real, y: real): void {
            const centre = width / 2;
            let angle = Math.atan2(y - centre, x - centre) * 180 / Math.PI;
            if (angle > 45 && angle < 135) {
                root.moved((angle < 90 ? 1 : 0) * root.to);
                return;
            }
            if (angle < 135)
                angle += 360;
            const normalized = Math.max(0, Math.min(1, (angle - 135) / 270));
            root.moved(normalized * root.to);
        }

        onPressed: event => updateValue(event.x, event.y)
        onPositionChanged: event => {
            if (pressed)
                updateValue(event.x, event.y);
        }
    }

    Timer {
        id: wheelInteractionTimer

        interval: 180
    }
}
