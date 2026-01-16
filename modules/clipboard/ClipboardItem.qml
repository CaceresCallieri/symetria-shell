pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import Quickshell
import QtQuick

Item {
    id: root

    required property var entry
    required property PersistentProperties visibilities

    implicitHeight: Config.clipboard.sizes.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    StateLayer {
        radius: Appearance.rounding.normal

        function onClicked(): void {
            Clipboard.restore(root.entry.id);
            root.visibilities.clipboard = false;
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Appearance.padding.larger
        anchors.rightMargin: Appearance.padding.larger
        anchors.margins: Appearance.padding.smaller

        // Icon indicating type
        MaterialIcon {
            id: icon

            text: root.entry.isImage ? "image" : "notes"
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Appearance.font.size.large

            anchors.verticalCenter: parent.verticalCenter
        }

        // Preview text
        StyledText {
            id: preview

            anchors.left: icon.right
            anchors.right: deleteBtn.left
            anchors.leftMargin: Appearance.spacing.normal
            anchors.rightMargin: Appearance.spacing.normal
            anchors.verticalCenter: icon.verticalCenter

            text: root.entry.preview
            font.pointSize: Appearance.font.size.normal
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        // Delete button
        Item {
            id: deleteBtn

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            implicitWidth: deleteIcon.implicitWidth + Appearance.padding.small * 2
            implicitHeight: deleteIcon.implicitHeight + Appearance.padding.small * 2

            opacity: deleteMouse.containsMouse ? 1 : 0.5

            Behavior on opacity {
                Anim {
                    duration: Appearance.anim.durations.small
                }
            }

            MouseArea {
                id: deleteMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Clipboard.remove(root.entry.id)
            }

            MaterialIcon {
                id: deleteIcon
                anchors.centerIn: parent
                text: "close"
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.small
            }
        }
    }
}
