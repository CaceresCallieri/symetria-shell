import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

PillCardSection {
    id: root

    implicitWidth: layout.implicitWidth + root.contentMargins * 2

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Appearance.spacing.small

        StyledText {
            text: qsTr("Capslock: %1").arg(Hypr.capsLock ? "Enabled" : "Disabled")
        }

        StyledText {
            text: qsTr("Numlock: %1").arg(Hypr.numLock ? "Enabled" : "Disabled")
        }
    }
}
