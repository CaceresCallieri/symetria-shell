import qs.components
import qs.services
import qs.config
import Quickshell
import QtQuick

StyledRect {
    id: root

    required property ShellScreen screen
    required property Session session

    // intentional var: heterogeneous JS object { background: color, border: color } from pillStyle()
    readonly property var pill: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)

    implicitHeight: text.implicitHeight + Appearance.padding.normal
    color: pill.background
    border.color: pill.border
    border.width: 1

    StyledText {
        id: text

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom

        text: qsTr("Symmetria Settings - %1").arg(root.session.active)
        font.capitalization: Font.Capitalize
        font.pointSize: Appearance.font.size.larger
        font.weight: 500
    }

    Item {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Appearance.padding.normal

        implicitWidth: implicitHeight
        implicitHeight: closeIcon.implicitHeight + Appearance.padding.small

        StateLayer {
            radius: Appearance.rounding.full

            function onClicked(): void {
                QsWindow.window.destroy();
            }
        }

        MaterialIcon {
            id: closeIcon

            anchors.centerIn: parent
            text: "close"
        }
    }
}
