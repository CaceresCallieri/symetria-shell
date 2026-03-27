import qs.components
import qs.components.effects
import qs.services
import qs.config
import QtQuick

Item {
    id: root

    readonly property bool active: Recorder.running
    readonly property int circleSize: 40

    visible: opacity > 0
    opacity: active ? 1 : 0
    scale: active ? 1 : 0.7
    implicitWidth: circleSize
    implicitHeight: circleSize

    Behavior on opacity {
        Anim {}
    }

    Behavior on scale {
        Anim {}
    }

    Rectangle {
        id: circle

        anchors.fill: parent
        radius: width / 2
        color: Recorder.paused ? Colours.palette.m3tertiary : Colours.palette.m3error

        Behavior on color {
            CAnim {}
        }

        Elevation {
            anchors.fill: parent
            radius: parent.radius
            z: -1
            level: 3
        }

        Rectangle {
            id: dot

            anchors.centerIn: parent
            width: 14
            height: 14
            radius: width / 2
            color: Recorder.paused ? Colours.palette.m3onTertiary : Colours.palette.m3onError

            Behavior on color {
                CAnim {}
            }

            SequentialAnimation on opacity {
                running: root.active && !Recorder.paused
                alwaysRunToEnd: true
                loops: Animation.Infinite

                Anim {
                    from: 1
                    to: 0
                    duration: Appearance.anim.durations.large
                    easing.bezierCurve: Appearance.anim.curves.emphasizedAccel
                }

                Anim {
                    from: 0
                    to: 1
                    duration: Appearance.anim.durations.extraLarge
                    easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        visible: root.active
        enabled: root.active
        cursorShape: Qt.PointingHandCursor
        onClicked: Recorder.stop()
    }
}
