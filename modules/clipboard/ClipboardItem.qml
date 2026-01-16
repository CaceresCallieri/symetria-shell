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

        // Icon indicating type
        MaterialIcon {
            id: icon

            text: root.entry.isImage ? "image" : "notes"
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Appearance.font.size.large

            anchors.verticalCenter: parent.verticalCenter
        }

        // Preview text with search highlighting
        HighlightedText {
            id: preview

            anchors.left: icon.right
            anchors.right: parent.right
            anchors.leftMargin: Appearance.spacing.normal
            anchors.verticalCenter: icon.verticalCenter

            sourceText: root.entry.preview
            searchQuery: root.searchQuery
            font.pointSize: Appearance.font.size.normal
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
}
