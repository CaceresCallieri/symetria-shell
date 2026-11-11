import qs.services
import QtQuick

Rectangle {
    required property Item target

    anchors.fill: parent
    anchors.margins: -3
    color: "transparent"
    radius: height / 2
    border.width: 2
    border.color: Colours.palette.m3onSurface
    visible: target.activeFocus
}
