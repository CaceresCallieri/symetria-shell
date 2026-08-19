pragma ComponentBehavior: Bound

import qs.components
import qs.services
import QtQuick

/// The volume dial: a machined knob turning inside a printed scale.
///
/// Visuals only — value handling, drag and wheel live in RotaryControl.
RotaryControl {
    id: root

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
                    width: tick.index % 5 === 0 ? Math.max(2, root.u(2.5)) : 1
                    height: tick.index % 5 === 0 ? Math.round(root.u(14)) : Math.round(root.u(8))
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
        width: Math.round(root.u(128))
        height: width
        radius: width / 2
        color: Qt.rgba(0.015, 0.018, 0.022, 0.94)
        border.width: Math.max(1, root.u(2))
        border.color: Qt.rgba(0.42, 0.45, 0.48, 0.32)
    }

    PillSurface {
        id: knobBody

        anchors.centerIn: parent
        width: Math.round(root.u(116))
        height: width
        radius: width / 2
        color: Qt.rgba(0.48, 0.50, 0.52, 1)
        borderWidth: Math.max(1, root.u(2))
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
                width: Math.max(5, root.u(9))
                height: width
                anchors.top: parent.top
                anchors.topMargin: Math.round(root.u(14))
                anchors.horizontalCenter: parent.horizontalCenter
                radius: width / 2
                color: Qt.rgba(0.035, 0.045, 0.055, 1)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.46)
            }
        }
    }
}
