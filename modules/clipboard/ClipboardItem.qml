pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.config
import Quickshell
import QtQuick

Item {
    id: root

    required property var entry
    required property PersistentProperties visibilities
    property string searchQuery: ""

    // Null-safe property access for entry fields
    readonly property bool isImage: entry?.isImage ?? false
    readonly property string imagePath: entry?.imagePath ?? ""
    readonly property string preview: entry?.preview ?? ""

    // Image items use 2x height for better thumbnail visibility (96px vs 48px)
    implicitHeight: root.isImage
        ? Config.clipboard.sizes.itemHeight * 2
        : Config.clipboard.sizes.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    // Accessibility for screen readers
    Accessible.role: Accessible.Button
    Accessible.name: root.isImage ? qsTr("Image clipboard entry") : root.preview
    Accessible.description: (root.entry?._kind === "transcription")
        ? qsTr("Click to copy transcription to clipboard")
        : qsTr("Click to restore to clipboard")

    StateLayer {
        radius: Appearance.rounding.normal

        function onClicked(): void {
            // Transcription entries (synthetic shape from Content.qml) carry
            // a `_kind` tag. They route through TranscriptionStore.paste()
            // (wl-copy + cliphist delete-query scrub) so the user can paste
            // immediately with Ctrl+V without polluting the Text tab.
            // Clipboard.restore() is the cliphist round-trip path.
            if (root.entry?._kind === "transcription")
                TranscriptionStore.paste(root.entry.id);
            else
                Clipboard.restore(root.entry.id);
            root.visibilities.clipboard = false;
        }
    }

    // ===== IMAGE LAYOUT (centered thumbnail, no text) =====
    Item {
        id: imageLayout

        visible: root.isImage
        anchors.fill: parent
        anchors.leftMargin: Appearance.padding.larger
        anchors.rightMargin: Appearance.padding.larger
        anchors.topMargin: Appearance.padding.smaller
        anchors.bottomMargin: Appearance.padding.smaller

        // Loading indicator while image decodes
        MaterialIcon {
            id: loadingIcon

            visible: root.imagePath === ""
            anchors.centerIn: parent

            text: "image"
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Appearance.font.size.extraLarge

            // Subtle pulse animation during load
            SequentialAnimation on opacity {
                running: loadingIcon.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.4; duration: 600; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
            }
        }

        // Thumbnail with rounded corners via OpacityMask
        Image {
            id: thumbnailImage

            visible: root.imagePath !== ""

            // Square thumbnail centered in available space
            width: parent.height
            height: parent.height
            anchors.centerIn: parent

            source: root.imagePath ? `file://${root.imagePath}` : ""
            sourceSize.width: 192
            sourceSize.height: 192
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            cache: true

            layer.enabled: root.imagePath !== ""
            layer.effect: OpacityMask {
                maskSource: thumbnailMask
            }
        }

        // Hidden mask for rounded corners
        Rectangle {
            id: thumbnailMask

            anchors.fill: thumbnailImage
            radius: Appearance.rounding.normal
            layer.enabled: true
            visible: false
        }
    }

    // ===== TEXT LAYOUT (icon + preview text) =====
    Item {
        id: textLayout

        visible: !root.isImage
        anchors.fill: parent
        anchors.leftMargin: Appearance.padding.larger
        anchors.rightMargin: Appearance.padding.larger
        anchors.topMargin: Appearance.padding.smaller
        anchors.bottomMargin: Appearance.padding.smaller

        MaterialIcon {
            id: icon

            text: "notes"
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Appearance.font.size.large

            anchors.verticalCenter: parent.verticalCenter
        }

        HighlightedText {
            id: previewText

            anchors.left: icon.right
            anchors.right: parent.right
            anchors.leftMargin: Appearance.spacing.normal
            anchors.verticalCenter: parent.verticalCenter

            sourceText: root.preview
            searchQuery: root.searchQuery
            // Smaller body size so more characters survive ElideRight per row,
            // letting the user scan more clipboard / transcription content at
            // a glance. Icon at .large stays as the row's visual anchor.
            font.pointSize: Appearance.font.size.small
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
}
