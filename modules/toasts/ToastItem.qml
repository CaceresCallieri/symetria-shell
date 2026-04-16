import qs.components
import qs.components.effects
import qs.services
import qs.config
import Symmetria
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

StyledRect {
    id: root

    required property Toast modelData

    readonly property bool hasImage: root.modelData.imagePath !== ""
    readonly property url imageUrl: root.hasImage ? (`file://${root.modelData.imagePath}`) : ""
    readonly property int maxWidth: Config.utilities.sizes.toastWidth - Appearance.padding.normal * 2
    readonly property int previewHeight: 140

    // Content-adaptive width: image toasts shrink to fit the image's
    // natural aspect ratio; text-only toasts keep the full config width.
    implicitWidth: {
        if (!hasImage || previewImage.status !== Image.Ready)
            return maxWidth;
        const aspectRatio = previewImage.implicitWidth / Math.max(1, previewImage.implicitHeight);
        const imageWidth = Math.round(previewHeight * aspectRatio);
        // Content width = image + padding on both sides
        const contentWidth = imageWidth + Appearance.padding.normal * 2;
        // At minimum, be as wide as the header row needs
        const headerMinWidth = headerRow.implicitWidth + Appearance.padding.normal * 2;
        return Math.min(Math.max(contentWidth, headerMinWidth), maxWidth);
    }
    implicitHeight: layout.implicitHeight + Appearance.padding.normal * 2

    readonly property color toastBaseColor: {
        if (root.modelData.type === Toast.Success)
            return Colours.palette.m3success;
        if (root.modelData.type === Toast.Warning)
            return Colours.palette.m3secondary;
        if (root.modelData.type === Toast.Error)
            return Colours.palette.m3error;
        return Colours.palette.m3surfaceContainerHigh;
    }
    readonly property var toastStyle: Colours.pillStyle(toastBaseColor, Colours.glass.medium)

    radius: Appearance.rounding.normal
    color: toastStyle.background
    border.width: 1
    border.color: toastStyle.border

    Elevation {
        anchors.fill: parent
        radius: parent.radius
        opacity: parent.opacity
        z: -1
        level: 3
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Appearance.padding.normal
        spacing: Appearance.spacing.small

        // Top row: icon + title/message (always present)
        RowLayout {
            id: headerRow

            Layout.fillWidth: true
            spacing: Appearance.spacing.normal

            StyledRect {
                readonly property var iconStyle: Colours.pillStyle(root.toastBaseColor, Colours.glass.strong)

                radius: Appearance.rounding.normal
                color: iconStyle.background
                border.width: 1
                border.color: iconStyle.border

                implicitWidth: implicitHeight
                implicitHeight: icon.implicitHeight + Appearance.padding.smaller * 2

                MaterialIcon {
                    id: icon

                    anchors.centerIn: parent
                    text: root.modelData.icon
                    color: Colours.palette.m3onSurface
                    font.pointSize: Math.round(Appearance.font.size.large * 1.2)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    id: title

                    Layout.fillWidth: true
                    text: root.modelData.title
                    color: Colours.palette.m3onSurface
                    font.pointSize: Appearance.font.size.normal
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    textFormat: Text.StyledText
                    text: root.modelData.message
                    color: Colours.palette.m3onSurfaceVariant
                    opacity: 0.8
                    elide: Text.ElideRight
                }
            }
        }

        // Image preview (only for image toasts)
        ClippingRectangle {
            visible: root.hasImage
            Layout.fillWidth: true
            Layout.preferredHeight: root.previewHeight

            radius: Appearance.rounding.small
            color: "transparent"

            Image {
                id: previewImage

                anchors.fill: parent
                source: root.imageUrl
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize: Qt.size(512, 512)
            }
        }
    }

    Behavior on implicitWidth {
        Anim {}
    }

    Behavior on color {
        CAnim {}
    }

    Behavior on border.color {
        CAnim {}
    }
}
