import qs.components
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    implicitWidth: layout.implicitWidth + Appearance.padding.large * 2
    implicitHeight: layout.implicitHeight + Appearance.padding.large * 2

    PillCard {
        anchors.fill: parent
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Appearance.padding.large
        anchors.rightMargin: Appearance.padding.large
        spacing: Appearance.spacing.normal

        StyledText {
            text: qsTr("Keyboard layout: %1").arg(Hypr.kbLayoutFull)
            font.weight: 500
        }

        // Always-raised neumorphic action pill — never `active: true`, so
        // it reads as press-able rather than a toggle. The StateLayer
        // handles the click ripple inside the pill body.
        PillToggleSurface {
            id: switchBtn

            Layout.fillWidth: true
            implicitHeight: switchLabel.implicitHeight + Appearance.padding.normal * 2
            active: false

            StateLayer {
                color: Colours.palette.m3onSurface

                function onClicked(): void {
                    Hypr.extras.message("switchxkblayout all next");
                }
            }

            StyledText {
                id: switchLabel
                anchors.centerIn: parent
                text: qsTr("Switch layout")
                color: Colours.palette.m3onSurface
            }
        }
    }
}
