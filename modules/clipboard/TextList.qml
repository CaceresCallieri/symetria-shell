pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import QtQuick

/// Progressive text entry list for the clipboard Text tab.
/// Uses a ListModel with lazy append() loading for smooth scrolling.
/// Loaded by Content.qml's Pane Loader via sourceComponent wrapper.
Item {
    id: root

    required property var entries        // ListModel for progressive loading
    required property var allEntries     // Full JS array for entry lookup
    required property bool hasMore
    required property var loadMore       // () => void
    required property PersistentProperties visibilities
    required property string searchQuery
    required property real maxHeight

    // Expose currentIndex for external access (keyboard navigation)
    property alias currentIndex: textList.currentIndex

    implicitWidth: Config.clipboard.sizes.itemWidth
    implicitHeight: root.entries.count > 0 ? textList.height + Appearance.spacing.normal : emptyText.implicitHeight

    StyledListView {
        id: textList

        visible: root.entries.count > 0
        model: root.entries
        width: Config.clipboard.sizes.itemWidth
        height: Math.min(contentHeight, root.maxHeight)
        clip: true
        spacing: Appearance.spacing.small
        topMargin: Appearance.spacing.normal
        orientation: Qt.Vertical
        reuseItems: true

        // Infinite scroll: load more entries when approaching bottom
        onContentYChanged: _checkLoadMore()
        onContentHeightChanged: _checkLoadMore()

        function _checkLoadMore(): void {
            if (!root.hasMore)
                return;
            const threshold = 100;
            if (contentY + height >= contentHeight - threshold)
                root.loadMore();
        }

        footer: Item {
            width: textList.width
            height: root.hasMore ? spinner.implicitHeight + Appearance.padding.large * 2 : 0
            visible: root.hasMore

            CircularIndicator {
                id: spinner
                anchors.centerIn: parent
                implicitSize: Appearance.font.size.large * 2
                strokeWidth: Appearance.padding.small * 0.5
                fgColour: Colours.palette.m3onSurfaceVariant
                bgColour: "transparent"
                running: parent.visible
            }
        }

        preferredHighlightBegin: 0
        preferredHighlightEnd: height
        highlightRangeMode: ListView.ApplyRange

        highlightFollowsCurrentItem: false
        highlight: StyledRect {
            radius: Appearance.rounding.normal
            color: Colours.palette.m3onSurface
            opacity: 0.08

            y: textList.currentItem?.y ?? 0
            implicitWidth: textList.width
            implicitHeight: textList.currentItem?.implicitHeight ?? 0

            Behavior on y {
                Anim {
                    duration: Appearance.anim.durations.expressiveDefaultSpatial
                    easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
                }
            }
        }

        delegate: ClipboardItem {
            required property int idx
            required property int index

            entry: root.allEntries[idx]
            visibilities: root.visibilities
            searchQuery: root.searchQuery
        }

        move: Transition {
            Anim {
                property: "y"
            }
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
                property: "y"
            }
            Anim {
                properties: "opacity,scale"
                to: 1
            }
        }

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: textList
        }
    }

    // Empty state for text tab
    Row {
        id: emptyText

        visible: root.entries.count === 0
        readonly property bool isSearchEmpty: root.searchQuery !== ""

        opacity: visible ? 1 : 0
        scale: visible ? 1 : 0.5

        spacing: Appearance.spacing.normal
        padding: Appearance.padding.large

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        MaterialIcon {
            text: emptyText.isSearchEmpty ? "search_off" : "content_paste_off"
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Appearance.font.size.extraLarge

            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                text: emptyText.isSearchEmpty ? qsTr("No matches found") : qsTr("No text in clipboard")
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.larger
                font.weight: 500
            }

            StyledText {
                text: emptyText.isSearchEmpty ? qsTr("Try a different search") : qsTr("Copy some text to get started")
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
