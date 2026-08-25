pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.containers
import qs.components.misc
import qs.services
import qs.config
import Quickshell
import QtQuick

/// Main content for the packages drawer.
///
/// Two view states:
/// 1. Search view — search bar + result list (default)
/// 2. Detail view — back header + scrollable package details
///
/// Transitions are driven by Packages.selectedDetail / Packages.fetchingDetail.
FocusScope {
    id: root

    required property PersistentProperties visibilities
    required property real maxHeight

    readonly property int padding: Appearance.padding.large

    /// Whether the detail view is active (fetching or showing)
    readonly property bool showingDetail: Packages.selectedDetail !== null || Packages.fetchingDetail

    /// Whether the user has navigated the result list with arrow keys
    property bool hasNavigated: false

    function focusSearch(): void {
        searchWrapper.focusTarget.forceActiveFocus();
    }

    function executeSearch(): void {
        const trimmed = searchWrapper.text.trim();
        if (trimmed.length >= 2 && trimmed !== Packages.currentQuery) {
            Packages.search(trimmed);
        }
    }

    // Global Escape handler: back from detail → close drawer
    Keys.onEscapePressed: {
        if (root.showingDetail) {
            Packages.clearDetail();
            searchWrapper.focusTarget.forceActiveFocus();
        } else {
            root.visibilities.packages = false;
        }
    }

    // Enter in detail view → copy install command
    Keys.onReturnPressed: {
        if (root.showingDetail && Packages.selectedDetail)
            detailView.triggerCopy();
    }

    Keys.onEnterPressed: {
        if (root.showingDetail && Packages.selectedDetail)
            detailView.triggerCopy();
    }

    // When entering detail mode, defocus the search field and grab focus
    // on the root FocusScope so Keys handlers (Escape, Enter) work.
    // Note: FocusScope.forceActiveFocus() alone does NOT remove activeFocus
    // from a child — a hidden TextField still receives key events.
    onShowingDetailChanged: {
        if (showingDetail) {
            searchWrapper.focusTarget.focus = false;
            root.forceActiveFocus();
        } else {
            searchWrapper.focusTarget.forceActiveFocus();
        }
    }

    FocusManager {
        active: root.visibilities.packages
        target: searchWrapper.focusTarget
        onClose: () => {
            searchWrapper.text = "";
            root.hasNavigated = false;
            Packages.cancelSearch();
            Packages.clearDetail();
            Packages.hasSearched = false;
        }
    }

    // Handle searchFromDetail: update search text and trigger search
    Connections {
        target: Packages

        function onSearchFromDetailRequested(name: string): void {
            searchWrapper.text = name;
            Packages.search(name);
            searchWrapper.focusTarget.forceActiveFocus();
        }
    }

    implicitWidth: Config.packages.sizes.width + padding * 2
    implicitHeight: {
        if (root.showingDetail) {
            let h = detailHeader.implicitHeight + padding * 2;
            if (detailSection.visible)
                h += detailSection.implicitHeight + padding;
            return Math.min(root.maxHeight, h);
        }

        let h = searchWrapper.implicitHeight + padding * 2;
        if (resultSection.visible)
            h += resultSection.implicitHeight + padding;
        return Math.min(root.maxHeight, h);
    }

    // ===== Search bar (top, hidden in detail view) =====
    PackagesSearchBar {
        id: searchWrapper

        visible: !root.showingDetail
        padding: root.padding

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.padding
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

        onSearchTextEdited: text => {
            root.hasNavigated = false;
            if (!text) {
                Packages.clearResults();
                Packages.hasSearched = false;
            }
        }

        onAccepted: {
            if (root.hasNavigated && resultList.count > 0 && resultList.currentIndex >= 0) {
                const entry = Packages.results[resultList.currentIndex];
                if (entry)
                    Packages.fetchDetail(entry.name, entry.installed);
            } else {
                root.executeSearch();
            }
        }

        onNavigateUp: {
            if (resultList.count > 0 && resultList.currentIndex > 0) {
                resultList.currentIndex--;
                root.hasNavigated = true;
            }
        }

        onNavigateDown: {
            if (resultList.count > 0 && resultList.currentIndex < resultList.count - 1) {
                resultList.currentIndex++;
                root.hasNavigated = true;
            }
        }

        onSearchRequested: root.executeSearch()
    }

    // ===== Detail header (top, visible in detail view) =====
    PackagesDetailHeader {
        id: detailHeader

        visible: root.showingDetail

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.padding
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

        onBackRequested: Packages.clearDetail()
    }

    // ===== Detail section (below detail header) =====
    Item {
        id: detailSection

        visible: root.showingDetail

        anchors.top: detailHeader.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.padding
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

        implicitHeight: {
            if (Packages.fetchingDetail)
                return detailLoadingState.implicitHeight;
            if (Packages.detailError)
                return detailErrorState.implicitHeight;
            if (Packages.selectedDetail)
                return detailView.height;
            return 0;
        }

        // Detail loading spinner
        Row {
            id: detailLoadingState

            visible: Packages.fetchingDetail
            spacing: Appearance.spacing.normal
            padding: Appearance.padding.large
            anchors.horizontalCenter: parent.horizontalCenter

            CircularIndicator {
                running: detailLoadingState.visible
                implicitSize: Appearance.font.size.large * 2
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: qsTr("Loading package details...")
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.normal
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Detail error state
        Row {
            id: detailErrorState

            visible: !Packages.fetchingDetail && Packages.detailError !== ""
            spacing: Appearance.spacing.normal
            padding: Appearance.padding.large
            anchors.horizontalCenter: parent.horizontalCenter

            MaterialIcon {
                text: "error_outline"
                color: Colours.palette.m3error
                font.pointSize: Appearance.font.size.extraLarge
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    text: Packages.detailError
                    color: Colours.palette.m3error
                    font.pointSize: Appearance.font.size.larger
                    font.weight: 500
                }

                StyledText {
                    text: qsTr("Press Escape or click back to return")
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Appearance.font.size.normal
                }
            }
        }

        // Detail view (scrollable)
        DetailView {
            id: detailView

            visible: !Packages.fetchingDetail && Packages.detailError === "" && Packages.selectedDetail !== null
            detail: Packages.selectedDetail

            width: parent.width
            height: Math.min(contentHeight, root.maxHeight - detailHeader.implicitHeight - root.padding * 3)
        }
    }

    // ===== Result section (below search, hidden in detail view) =====
    Item {
        id: resultSection

        visible: !root.showingDetail && (Packages.searching || Packages.hasSearched)

        anchors.top: searchWrapper.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.padding
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

        implicitHeight: {
            if (Packages.searching && Packages.results.length === 0)
                return loadingState.implicitHeight;
            if (Packages.results.length > 0)
                return resultList.height;
            if (Packages.hasSearched)
                return emptyState.implicitHeight;
            return 0;
        }

        // Loading spinner
        Row {
            id: loadingState

            visible: Packages.searching && Packages.results.length === 0
            spacing: Appearance.spacing.normal
            padding: Appearance.padding.large
            anchors.horizontalCenter: parent.horizontalCenter

            CircularIndicator {
                running: loadingState.visible
                implicitSize: Appearance.font.size.large * 2
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: qsTr("Searching packages...")
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.normal
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Result list
        StyledListView {
            id: resultList

            visible: Packages.results.length > 0
            model: Packages.results
            width: Config.packages.sizes.width
            clip: true
            spacing: Appearance.spacing.small
            orientation: Qt.Vertical
            reuseItems: true

            height: Math.min(contentHeight, (Config.packages.sizes.itemHeight + spacing) * Config.packages.maxShown - spacing, root.maxHeight - searchWrapper.implicitHeight - root.padding * 3)

            onModelChanged: {
                currentIndex = 0;
                root.hasNavigated = false;
            }

            preferredHighlightBegin: 0
            preferredHighlightEnd: height
            highlightRangeMode: ListView.ApplyRange

            highlightFollowsCurrentItem: false
            highlight: StyledRect {
                radius: Appearance.rounding.normal
                color: Colours.palette.m3onSurface
                opacity: 0.08

                y: resultList.currentItem?.y ?? 0
                implicitWidth: resultList.width
                implicitHeight: resultList.currentItem?.implicitHeight ?? 0

                Behavior on y {
                    Anim {
                        duration: Appearance.anim.durations.expressiveDefaultSpatial
                        easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
                    }
                }
            }

            delegate: PackageItem {}

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
                flickable: resultList
            }
        }

        // Empty state
        Row {
            id: emptyState

            visible: !Packages.searching && Packages.hasSearched && Packages.results.length === 0

            spacing: Appearance.spacing.normal
            padding: Appearance.padding.large

            anchors.horizontalCenter: parent.horizontalCenter

            MaterialIcon {
                text: "search_off"
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.extraLarge
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    text: qsTr("No packages found")
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Appearance.font.size.larger
                    font.weight: 500
                }

                StyledText {
                    text: qsTr("Try a different search term")
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Appearance.font.size.normal
                }
            }
        }
    }

    Behavior on implicitHeight {
        enabled: root.visibilities.packages

        Anim {
            duration: Appearance.anim.durations.large
            easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
        }
    }
}
