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
    property string searchQuery: ""

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

        // Icon for text entries OR loading state for images without thumbnail
        MaterialIcon {
            id: icon

            visible: !root.entry.isImage || root.entry.imagePath === ""
            text: root.entry.isImage ? "image" : "notes"
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Appearance.font.size.large

            anchors.verticalCenter: parent.verticalCenter
        }

        // Thumbnail container for image entries (with rounded corners)
        Item {
            id: thumbnailContainer

            visible: root.entry.isImage && root.entry.imagePath !== ""
            width: parent.height - Appearance.padding.smaller * 2
            height: width

            anchors.verticalCenter: parent.verticalCenter

            // Rounded clip container
            Rectangle {
                id: thumbnailClip

                anchors.fill: parent
                radius: Appearance.rounding.small
                color: Colours.palette.m3surfaceContainerHighest
                clip: true

                Image {
                    id: thumbnail

                    anchors.fill: parent
                    source: root.entry.imagePath ? `file://${root.entry.imagePath}` : ""
                    sourceSize.width: 128   // Qt only decodes to this size (memory efficient)
                    sourceSize.height: 128
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                }
            }
        }

        // Preview text with search highlighting
        HighlightedText {
            id: preview

            anchors.left: (thumbnailContainer.visible ? thumbnailContainer : icon).right
            anchors.right: parent.right
            anchors.leftMargin: Appearance.spacing.normal
            anchors.verticalCenter: parent.verticalCenter

            sourceText: root.entry.preview
            searchQuery: root.searchQuery
            font.pointSize: Appearance.font.size.normal
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
}
