pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property alias leading: leadingSlot.sourceComponent
    property alias heading: headingSlot.sourceComponent
    property alias trailing: trailingSlot.sourceComponent
    readonly property Item trailingItem: trailingSlot.item as Item

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row

        anchors.fill: parent
        spacing: 12

        Loader {
            id: leadingSlot
            Layout.alignment: Qt.AlignVCenter
        }
        Loader {
            id: headingSlot
            // A nested ColumnLayout propagated its text's maximum width,
            // so the close button stayed next to the title. This slot owns
            // the expandable space independently of the heading contents.
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignVCenter
        }
        Loader {
            id: trailingSlot
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
