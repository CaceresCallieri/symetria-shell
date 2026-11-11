pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Button {
    id: root

    property string iconName: ""
    property bool selected: false
    property bool closeControl: false
    readonly property var style: Colours.pillStyle(selected ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh, hovered ? Colours.glass.strong : Colours.glass.medium) // intentional var: theme style

    implicitWidth: closeControl ? 32 : contentItem.implicitWidth + 32
    implicitHeight: closeControl ? 32 : 40
    padding: closeControl ? 0 : 12
    focusPolicy: Qt.StrongFocus
    Accessible.name: closeControl ? "Cerrar selector" : text

    background: Item {
        PillSurface {
            anchors.fill: parent
            visible: !root.closeControl
            color: root.style.background
            borderColor: root.style.border
        }
        Rectangle {
            anchors.centerIn: parent
            visible: root.closeControl
            width: 13
            height: 13
            radius: width / 2
            color: root.hovered ? "#ff786f" : "#ff5f57"
        }
        FocusRing {
            target: root
        }
    }

    contentItem: CenteredRow {
        spacing: 8
        visible: !root.closeControl
        MaterialIcon {
            Layout.alignment: Qt.AlignVCenter
            visible: root.iconName !== ""
            text: root.iconName
            color: Colours.palette.m3onSurface
        }
        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: root.text
            font.family: Appearance.font.family.mono
            opacity: root.enabled ? 1 : 0.45
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}
