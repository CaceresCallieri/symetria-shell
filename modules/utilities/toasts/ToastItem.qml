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

    anchors.left: parent.left
    anchors.right: parent.right
    implicitHeight: layout.implicitHeight + Appearance.padding.smaller * 2

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

    RowLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Appearance.padding.smaller
        anchors.leftMargin: Appearance.padding.normal
        anchors.rightMargin: Appearance.padding.normal
        spacing: Appearance.spacing.normal

        // Image thumbnail when imagePath is set, Material icon otherwise
        Loader {
            id: iconLoader

            readonly property bool hasImage: root.modelData.imagePath !== ""
            readonly property var iconStyle: Colours.pillStyle(root.toastBaseColor, Colours.glass.strong)

            sourceComponent: hasImage ? imageComponent : iconComponent
        }

        Component {
            id: iconComponent

            StyledRect {
                radius: Appearance.rounding.normal
                color: iconLoader.iconStyle.background
                border.width: 1
                border.color: iconLoader.iconStyle.border

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
        }

        Component {
            id: imageComponent

            ClippingRectangle {
                readonly property int thumbSize: Math.round(Appearance.font.size.large * 1.2) + Appearance.padding.smaller * 2

                radius: Appearance.rounding.normal
                implicitWidth: thumbSize
                implicitHeight: thumbSize
                color: "transparent"

                Image {
                    anchors.fill: parent
                    source: `file://${root.modelData.imagePath}`
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(256, 256)
                }
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

    Behavior on border.color {
        CAnim {}
    }
}
