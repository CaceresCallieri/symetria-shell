import qs.components
import qs.services
import qs.config
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
        spacing: Appearance.spacing.small

        StyledText {
            text: qsTr("Capslock: %1").arg(Hypr.capsLock ? "Enabled" : "Disabled")
        }

        StyledText {
            text: qsTr("Numlock: %1").arg(Hypr.numLock ? "Enabled" : "Disabled")
        }
    }
}
