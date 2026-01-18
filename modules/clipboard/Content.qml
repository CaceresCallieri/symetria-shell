pragma ComponentBehavior: Bound

import "services"
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property PersistentProperties visibilities
    required property var panels
    required property real maxHeight

    readonly property int padding: Appearance.padding.large
    readonly property int rounding: Appearance.rounding.large

    // Double-click confirmation state for clear all
    property bool confirmClear: false

    // Debounced search text for performance (avoids searching on every keystroke)
    property string debouncedSearchText: ""

    // Filtered entries based on debounced search
    readonly property var filteredEntries: Search.search(debouncedSearchText)

    // Debounce timer for search input
    Timer {
        id: searchDebounce
        interval: 150
        onTriggered: root.debouncedSearchText = search.text
    }

    implicitWidth: Config.clipboard.sizes.itemWidth + padding * 2
    implicitHeight: listWrapper.height + searchWrapper.height + padding * 2

    // List wrapper (above search bar, like launcher)
    Item {
        id: listWrapper

        implicitWidth: list.width
        implicitHeight: root.filteredEntries.length > 0 ? list.height + root.padding : empty.height

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: searchWrapper.top
        anchors.bottomMargin: root.padding

        StyledListView {
            id: list

            visible: root.filteredEntries.length > 0
            model: root.filteredEntries
            width: Config.clipboard.sizes.itemWidth
            height: Math.min(contentHeight, root.maxHeight - searchWrapper.height - root.padding * 3)
            clip: true
            spacing: Appearance.spacing.small
            topMargin: Appearance.spacing.normal
            orientation: Qt.Vertical
            reuseItems: true
            implicitHeight: (Config.clipboard.sizes.itemHeight + spacing) * Math.min(Config.clipboard.maxDisplayed, count) - spacing

            preferredHighlightBegin: 0
            preferredHighlightEnd: height
            highlightRangeMode: ListView.ApplyRange

            highlightFollowsCurrentItem: false
            highlight: StyledRect {
                radius: Appearance.rounding.normal
                color: Colours.palette.m3onSurface
                opacity: 0.08

                y: list.currentItem?.y ?? 0
                implicitWidth: list.width
                implicitHeight: list.currentItem?.implicitHeight ?? 0

                Behavior on y {
                    Anim {
                        duration: Appearance.anim.durations.expressiveDefaultSpatial
                        easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
                    }
                }
            }

            delegate: ClipboardItem {
                required property var modelData
                required property int index

                entry: modelData
                visibilities: root.visibilities
                searchQuery: root.debouncedSearchText
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
                flickable: list
            }
        }

        // Empty state
        Row {
            id: empty

            visible: root.filteredEntries.length === 0
            readonly property bool isSearchEmpty: search.text !== ""

            opacity: visible ? 1 : 0
            scale: visible ? 1 : 0.5

            spacing: Appearance.spacing.normal
            padding: Appearance.padding.large

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            MaterialIcon {
                text: empty.isSearchEmpty ? "search_off" : "content_paste_off"
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.extraLarge

                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    text: empty.isSearchEmpty ? qsTr("No matches found") : qsTr("No clipboard history")
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Appearance.font.size.larger
                    font.weight: 500
                }

                StyledText {
                    text: empty.isSearchEmpty ? qsTr("Try a different search") : qsTr("Copy something to get started")
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

    // Search bar at bottom (like launcher)
    StyledRect {
        id: searchWrapper

        color: Colours.layer(Colours.palette.m3surfaceContainer, 2)
        radius: Appearance.rounding.full

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.padding

        implicitHeight: Math.max(searchIcon.implicitHeight, search.implicitHeight, clearIcon.implicitHeight)

        MaterialIcon {
            id: searchIcon

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: root.padding

            text: "search"
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledTextField {
            id: search

            anchors.left: searchIcon.right
            anchors.right: clearIcon.left
            anchors.leftMargin: Appearance.spacing.small
            anchors.rightMargin: Appearance.spacing.small

            topPadding: Appearance.padding.larger
            bottomPadding: Appearance.padding.larger

            placeholderText: qsTr("Search clipboard...")

            onTextChanged: searchDebounce.restart()

            onAccepted: {
                const item = list.currentItem;
                if (item && item.entry) {
                    Clipboard.restore(item.entry.id);
                    root.visibilities.clipboard = false;
                }
            }

            Keys.onUpPressed: {
                if (list.currentIndex > 0)
                    list.currentIndex--;
            }

            Keys.onDownPressed: {
                if (list.currentIndex < list.count - 1)
                    list.currentIndex++;
            }

            Keys.onEscapePressed: root.visibilities.clipboard = false

            Component.onCompleted: forceActiveFocus()

            Connections {
                target: root.visibilities

                function onClipboardChanged(): void {
                    if (root.visibilities.clipboard) {
                        Clipboard.refCount++;
                        search.forceActiveFocus();
                        list.currentIndex = 0;
                    } else {
                        Clipboard.refCount--;
                        // Clear search and reset state when drawer closes
                        search.text = "";
                        root.confirmClear = false;
                    }
                }
            }
        }

        // Clear search / Clear all button
        MaterialIcon {
            id: clearIcon

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: root.padding

            width: (search.text || Clipboard.entries.length > 0) ? implicitWidth : implicitWidth / 2
            opacity: {
                if (!search.text && Clipboard.entries.length === 0)
                    return 0;
                if (clearMouse.pressed)
                    return 0.7;
                if (clearMouse.containsMouse)
                    return 1;
                return 0.5;
            }

            text: {
                if (search.text)
                    return "close";
                if (root.confirmClear)
                    return "warning";
                return "delete_sweep";
            }
            color: root.confirmClear ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant

            Behavior on width {
                Anim { duration: Appearance.anim.durations.small }
            }

            Behavior on opacity {
                Anim { duration: Appearance.anim.durations.small }
            }

            Behavior on color {
                ColorAnimation { duration: Appearance.anim.durations.small }
            }

            MouseArea {
                id: clearMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onClicked: {
                    if (search.text) {
                        // Clear search text
                        search.text = "";
                        search.forceActiveFocus();
                    } else if (root.confirmClear) {
                        // Second click - actually clear
                        Clipboard.clear();
                        root.confirmClear = false;
                    } else {
                        // First click - request confirmation
                        root.confirmClear = true;
                        confirmTimer.restart();
                    }
                }
            }
        }
    }

    // Confirmation timeout for clear all
    Timer {
        id: confirmTimer
        interval: Config.clipboard.clearConfirmTimeout
        onTriggered: root.confirmClear = false
    }

    Behavior on implicitWidth {
        enabled: root.visibilities.clipboard

        Anim {
            duration: Appearance.anim.durations.large
            easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
        }
    }

    Behavior on implicitHeight {
        enabled: root.visibilities.clipboard

        Anim {
            duration: Appearance.anim.durations.large
            easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
        }
    }
}
