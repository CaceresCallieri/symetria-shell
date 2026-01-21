pragma ComponentBehavior: Bound

import "../../utils/scripts/fzf.js" as Fzf
import "../../utils/scripts/fuzzysort.js" as Fuzzy
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property PersistentProperties visibilities
    required property PersistentProperties state
    required property var panels
    required property real maxHeight

    readonly property int padding: Appearance.padding.large
    readonly property int rounding: Appearance.rounding.large

    // Tab indices for readability
    readonly property int tabText: 0
    readonly property int tabImages: 1

    // Double-click confirmation state for clear all
    property bool confirmClear: false

    // Debounced search text for performance (avoids searching on every keystroke)
    property string debouncedSearchText: ""

    // Get all entries (search-filtered if searching, otherwise all loaded entries)
    // Comma operator forces QML binding to depend on entries.length
    readonly property var allFilteredEntries: {
        Clipboard.entries.length;  // Dependency tracking
        if (!debouncedSearchText) return Clipboard.entries;

        // Direct FZF/Fuzzysort search on clipboard entries
        const useFuzzy = Config.clipboard.useFuzzy;
        if (useFuzzy) {
            return Fuzzy.go(debouncedSearchText, Clipboard.entries, {
                key: "preview", all: true
            }).map(r => r.obj);
        }
        return new Fzf.Finder(Clipboard.entries, {
            selector: e => e.preview
        }).find(debouncedSearchText).map(r => r.item);
    }

    // Helper: filter entries by type and apply display limit
    function filterByType(isImage: bool, limit: int): list<var> {
        return root.allFilteredEntries
            .filter(e => e.isImage === isImage)
            .slice(0, limit);
    }

    readonly property var textEntries: filterByType(false, Config.clipboard.maxDisplayed)
    readonly property var imageEntries: filterByType(true, Config.clipboard.maxImagesDisplayed)

    // Calculate estimated list height for text entries (images use grid)
    function calculateListHeight(): real {
        const entries = root.textEntries;
        const maxItems = Math.min(Config.clipboard.maxDisplayed, entries.length);
        const itemHeight = Config.clipboard.sizes.itemHeight;
        const spacing = Appearance.spacing.small;

        let totalHeight = 0;
        for (let i = 0; i < maxItems; i++) {
            totalHeight += itemHeight;
            if (i < maxItems - 1) totalHeight += spacing;
        }
        return totalHeight;
    }

    // Debounce timer for search input
    Timer {
        id: searchDebounce
        interval: 150
        onTriggered: root.debouncedSearchText = search.text
    }

    // Track if we've incremented refCount to avoid double increment/decrement
    property bool _refCounted: false

    // Handle visibility changes at root level to avoid race conditions
    Connections {
        target: root.visibilities

        function onClipboardChanged(): void {
            if (root.visibilities.clipboard) {
                if (!root._refCounted) {
                    root._refCounted = true;
                    Clipboard.refCount++;
                }
                search.forceActiveFocus();
                if (textPane.item)
                    textPane.item.currentIndex = 0;
                if (imagePane.item)
                    imagePane.item.currentIndex = 0;
            } else {
                if (root._refCounted) {
                    root._refCounted = false;
                    Clipboard.refCount--;
                }
                // Clear search and reset state when drawer closes
                search.text = "";
                root.confirmClear = false;
            }
        }
    }

    // Handle initial state if drawer is already open when component loads
    Component.onCompleted: {
        if (root.visibilities.clipboard && !root._refCounted) {
            root._refCounted = true;
            Clipboard.refCount++;
        }
    }

    Component.onDestruction: {
        if (root._refCounted) {
            Clipboard.refCount--;
        }
    }

    implicitWidth: Config.clipboard.sizes.itemWidth + padding * 2
    implicitHeight: tabs.implicitHeight + tabs.anchors.topMargin + contentWrapper.implicitHeight + searchWrapper.implicitHeight + padding * 3

    // Tabs at top
    Tabs {
        id: tabs

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Appearance.padding.normal
        anchors.margins: Appearance.padding.large

        nonAnimWidth: root.implicitWidth - anchors.margins * 2
        state: root.state
    }

    // Content area with horizontal swipe
    ClippingRectangle {
        id: contentWrapper

        anchors.top: tabs.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.padding
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

        height: implicitHeight
        radius: Appearance.rounding.normal
        color: "transparent"

        // Use fixed height (1/2 of max) for consistent sizing between tabs
        implicitHeight: root.maxHeight / 2

        Flickable {
            id: view

            readonly property int currentIndex: root.state.currentTab
            readonly property Item currentItem: row.children[currentIndex]

            anchors.fill: parent

            flickableDirection: Flickable.HorizontalFlick

            contentX: currentItem?.x ?? 0
            contentWidth: row.implicitWidth
            contentHeight: row.implicitHeight

            // Swipe gesture handling
            onContentXChanged: {
                if (!moving || !currentItem)
                    return;

                const x = contentX - currentItem.x;
                if (x > currentItem.implicitWidth / 2)
                    root.state.currentTab = Math.min(root.state.currentTab + 1, tabs.count - 1);
                else if (x < -currentItem.implicitWidth / 2)
                    root.state.currentTab = Math.max(root.state.currentTab - 1, 0);
            }

            onDragEnded: {
                if (!currentItem)
                    return;

                const x = contentX - currentItem.x;
                if (x > currentItem.implicitWidth / 10)
                    root.state.currentTab = Math.min(root.state.currentTab + 1, tabs.count - 1);
                else if (x < -currentItem.implicitWidth / 10)
                    root.state.currentTab = Math.max(root.state.currentTab - 1, 0);
                else
                    contentX = Qt.binding(() => currentItem?.x ?? 0);
            }

            RowLayout {
                id: row

                spacing: 0

                // Text tab pane
                Pane {
                    id: textPane
                    index: 0
                    sourceComponent: TextList {
                        entries: root.textEntries
                        visibilities: root.visibilities
                        searchQuery: root.debouncedSearchText
                        maxHeight: contentWrapper.implicitHeight
                    }
                }

                // Images tab pane
                Pane {
                    id: imagePane
                    index: 1
                    sourceComponent: ImageGrid {
                        entries: root.imageEntries
                        visibilities: root.visibilities
                        searchQuery: root.debouncedSearchText
                        maxHeight: contentWrapper.implicitHeight
                    }
                }
            }

            Behavior on contentX {
                Anim {}
            }
        }
    }

    // Search bar at bottom (like launcher)
    StyledRect {
        id: searchWrapper

        color: Colours.layer(Colours.palette.m3surfaceContainer, 2)
        radius: Appearance.rounding.full

        anchors.top: contentWrapper.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.padding
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

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
                if (root.state.currentTab === root.tabText) {
                    const textList = textPane.item;
                    if (!textList) return;
                    const entry = root.textEntries[textList.currentIndex];
                    if (entry) {
                        Clipboard.restore(entry.id);
                        root.visibilities.clipboard = false;
                    }
                } else {
                    const imageGrid = imagePane.item;
                    if (!imageGrid) return;
                    const entry = root.imageEntries[imageGrid.currentIndex];
                    if (entry) {
                        Clipboard.restore(entry.id);
                        root.visibilities.clipboard = false;
                    }
                }
            }

            Keys.onUpPressed: {
                if (root.state.currentTab === root.tabText) {
                    const textList = textPane.item;
                    if (!textList) return;
                    if (textList.currentIndex > 0)
                        textList.currentIndex--;
                } else {
                    const imageGrid = imagePane.item;
                    if (!imageGrid || root.imageEntries.length === 0) return;
                    const cols = imageGrid.columnCount;
                    if (imageGrid.currentIndex >= cols)
                        imageGrid.currentIndex -= cols;
                }
            }

            Keys.onDownPressed: {
                if (root.state.currentTab === root.tabText) {
                    const textList = textPane.item;
                    if (!textList) return;
                    if (textList.currentIndex < root.textEntries.length - 1)
                        textList.currentIndex++;
                } else {
                    const imageGrid = imagePane.item;
                    if (!imageGrid || root.imageEntries.length === 0) return;
                    const cols = imageGrid.columnCount;
                    const newIndex = imageGrid.currentIndex + cols;
                    if (newIndex < root.imageEntries.length)
                        imageGrid.currentIndex = newIndex;
                }
            }

            Keys.onLeftPressed: {
                if (root.state.currentTab === root.tabImages) {
                    const imageGrid = imagePane.item;
                    if (!imageGrid || root.imageEntries.length === 0) return;
                    if (imageGrid.currentIndex > 0)
                        imageGrid.currentIndex--;
                }
            }

            Keys.onRightPressed: {
                if (root.state.currentTab === root.tabImages) {
                    const imageGrid = imagePane.item;
                    if (!imageGrid || root.imageEntries.length === 0) return;
                    const newIndex = imageGrid.currentIndex + 1;
                    if (newIndex < root.imageEntries.length)
                        imageGrid.currentIndex = newIndex;
                }
            }

            Keys.onEscapePressed: root.visibilities.clipboard = false

            Keys.onPressed: event => {
                // Tab key cycles between tabs
                if (event.key === Qt.Key_Tab) {
                    root.state.currentTab = (root.state.currentTab + 1) % 2;
                    event.accepted = true;
                }
            }

            Component.onCompleted: forceActiveFocus()
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

    // Lazy-loading Pane component
    component Pane: Loader {
        required property int index

        Layout.alignment: Qt.AlignTop

        Component.onCompleted: active = Qt.binding(() => {
            // Load current pane plus adjacent panes for smooth swipe transitions.
            return Math.abs(index - view.currentIndex) <= 1;
        })
    }

    // Text list component for the Text tab
    component TextList: Item {
        id: textListRoot

        required property var entries
        required property PersistentProperties visibilities
        required property string searchQuery
        required property real maxHeight

        // Expose currentIndex for external access (keyboard navigation)
        property alias currentIndex: textList.currentIndex

        implicitWidth: Config.clipboard.sizes.itemWidth
        implicitHeight: textListRoot.entries.length > 0 ? textList.height + Appearance.spacing.normal : emptyText.implicitHeight

        StyledListView {
            id: textList

            visible: textListRoot.entries.length > 0
            model: textListRoot.entries
            width: Config.clipboard.sizes.itemWidth
            height: Math.min(contentHeight, textListRoot.maxHeight)
            clip: true
            spacing: Appearance.spacing.small
            topMargin: Appearance.spacing.normal
            orientation: Qt.Vertical
            reuseItems: true

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
                required property var modelData
                required property int index

                entry: modelData
                visibilities: textListRoot.visibilities
                searchQuery: textListRoot.searchQuery
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

            visible: textListRoot.entries.length === 0
            readonly property bool isSearchEmpty: textListRoot.searchQuery !== ""

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
}
