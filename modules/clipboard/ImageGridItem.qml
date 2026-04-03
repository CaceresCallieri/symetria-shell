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

    // Null-safe property access for entry fields
    readonly property string imagePath: entry?.imagePath ?? ""

    // Accessibility for screen readers
    Accessible.role: Accessible.Button
    Accessible.name: qsTr("Image clipboard entry")
    Accessible.description: qsTr("Click to restore to clipboard")

    StateLayer {
        radius: Appearance.rounding.normal

        function onClicked(): void {
            Clipboard.restore(root.entry.id);
            root.visibilities.clipboard = false;
        }
    }

    Item {
        id: imageContainer

        anchors.fill: parent
        anchors.margins: Appearance.spacing.small / 2

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
            anchors.fill: parent

            source: root.imagePath ? `file://${root.imagePath}` : ""
            sourceSize.width: 256
            sourceSize.height: 256
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            cache: true

            layer.enabled: true
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
}
