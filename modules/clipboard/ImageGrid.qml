pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import Quickshell
import QtQuick

Item {
    id: root

    required property var entries
    required property PersistentProperties visibilities
    required property real maxHeight
    property string searchQuery: ""

    readonly property int itemWidth: Config.clipboard.sizes.itemWidth
    readonly property int cellSize: 181

    implicitWidth: itemWidth
    implicitHeight: root.entries.length > 0 ? grid.height : empty.implicitHeight

    GridView {
        id: grid

        visible: root.entries.length > 0
        width: root.itemWidth
        height: Math.min(contentHeight, root.maxHeight)
        clip: true

        cellWidth: root.cellSize
        cellHeight: root.cellSize

        model: root.entries

        topMargin: Appearance.spacing.normal

        delegate: ImageGridItem {
            required property var modelData
            required property int index

            width: grid.cellWidth
            height: grid.cellHeight

            entry: modelData
            visibilities: root.visibilities
        }

        add: Transition {
            Anim {
                properties: "opacity,scale"
                from: 0
                to: 1
            }
        }

        remove: Transition {
            Anim {
                properties: "opacity,scale"
                from: 1
                to: 0
            }
        }

        displaced: Transition {
            Anim {
                properties: "x,y"
            }
        }

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: grid
        }
    }

    // Empty state for images tab
    Row {
        id: empty

        visible: root.entries.length === 0
        readonly property bool isSearchEmpty: root.searchQuery !== ""

        opacity: visible ? 1 : 0
        scale: visible ? 1 : 0.5

        spacing: Appearance.spacing.normal
        padding: Appearance.padding.large

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        MaterialIcon {
            text: empty.isSearchEmpty ? "search_off" : "hide_image"
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Appearance.font.size.extraLarge

            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                text: empty.isSearchEmpty ? qsTr("No matching images") : qsTr("No images in clipboard")
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.larger
                font.weight: 500
            }

            StyledText {
                text: empty.isSearchEmpty ? qsTr("Try a different search") : qsTr("Copy an image to see it here")
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.normal
            }
        }

        Behavior on opacity {
            Anim {}
        }

        Behavior on scale {
            Anim {}
        }
    }
}
