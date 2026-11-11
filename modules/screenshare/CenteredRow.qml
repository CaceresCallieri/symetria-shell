pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

// Center the complete icon/label group. Stretching the RowLayout to the
// button's width separated the icon from its label on wide mode buttons.
Item {
    id: root

    default property alias content: row.data
    property alias spacing: row.spacing

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    RowLayout {
        id: row

        anchors.centerIn: parent
        width: Math.min(root.width, implicitWidth)
        spacing: 8
    }
}
