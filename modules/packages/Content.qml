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

    function focusSearch(): void {
        search.forceActiveFocus();
    }

    // Global Escape handler: back from detail → close drawer
    Keys.onEscapePressed: {
        if (root.showingDetail) {
            Packages.clearDetail();
            search.forceActiveFocus();
        } else {
            root.visibilities.packages = false;
        }
    }

    // When entering detail mode, grab focus on the root FocusScope
    // so the global Escape handler works
    onShowingDetailChanged: {
        if (showingDetail)
            root.forceActiveFocus();
    }

    FocusManager {
        active: root.visibilities.packages
        target: search
        onClose: () => {
            search.text = "";
            Packages.cancelSearch();
            Packages.clearDetail();
            Packages.hasSearched = false;
        }
    }

    // Handle searchFromDetail: update search text and trigger search
    Connections {
        target: Packages

        function onSearchFromDetailRequested(name: string): void {
            search.text = name;
            Packages.search(name);
            search.forceActiveFocus();
        }
    }

    // Debounce timer for search input
    Timer {
        id: searchDebounce
        interval: Config.packages.debounceMs
        onTriggered: Packages.search(search.text)
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
    StyledRect {
        id: searchWrapper

        visible: !root.showingDetail

        color: Colours.layer(Colours.palette.m3surfaceContainer, 2)
        radius: Appearance.rounding.full

        anchors.top: parent.top
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

            placeholderText: qsTr("Search packages...")

            onTextChanged: {
                if (text.trim().length >= 2)
                    searchDebounce.restart();
                else {
                    searchDebounce.stop();
                    Packages.clearResults();
                    Packages.hasSearched = false;
                }
            }

            onAccepted: {
                // Enter fetches detail for highlighted item
                if (resultList.count > 0 && resultList.currentIndex >= 0) {
                    const entry = Packages.results[resultList.currentIndex];
                    if (entry)
                        Packages.fetchDetail(entry.name, entry.installed);
                }
            }

            Keys.onUpPressed: {
                if (resultList.count > 0 && resultList.currentIndex > 0)
                    resultList.currentIndex--;
            }

            Keys.onDownPressed: {
                if (resultList.count > 0 && resultList.currentIndex < resultList.count - 1)
                    resultList.currentIndex++;
            }

        }

        MaterialIcon {
            id: clearIcon

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: root.padding

            width: search.text ? implicitWidth : implicitWidth / 2
            opacity: {
                if (!search.text)
                    return 0;
                if (mouse.pressed)
                    return 0.7;
                if (mouse.containsMouse)
                    return 0.8;
                return 1;
            }

            text: "close"
            color: Colours.palette.m3onSurfaceVariant

            MouseArea {
                id: mouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: search.text ? Qt.PointingHandCursor : undefined

                onClicked: {
                    search.text = "";
                    search.forceActiveFocus();
                }
            }

            Behavior on width {
                Anim {
                    duration: Appearance.anim.durations.small
                }
            }

            Behavior on opacity {
                Anim {
                    duration: Appearance.anim.durations.small
                }
            }
        }
    }

    // ===== Detail header (top, visible in detail view) =====
    Item {
        id: detailHeader

        visible: root.showingDetail

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.padding
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

        implicitHeight: detailHeaderRow.implicitHeight

        Row {
            id: detailHeaderRow

            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Appearance.spacing.normal

            // Back button
            StyledRect {
                id: backButton

                implicitWidth: backIcon.implicitWidth + Appearance.padding.normal * 2
                implicitHeight: backIcon.implicitHeight + Appearance.padding.normal * 2
                radius: Appearance.rounding.full
                color: "transparent"
                anchors.verticalCenter: parent.verticalCenter

                MaterialIcon {
                    id: backIcon
                    anchors.centerIn: parent
                    text: "arrow_back"
                    color: Colours.palette.m3onSurface
                }

                StateLayer {
                    radius: parent.radius

                    function onClicked(): void {
                        Packages.clearDetail();
                    }
                }
            }

            // Package name + version
            Column {
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    spacing: Appearance.spacing.small

                    StyledText {
                        text: Packages.selectedDetail?.name ?? ""
                        font.pointSize: Appearance.font.size.larger
                        font.weight: Font.Medium
                    }

                    StyledText {
                        text: Packages.selectedDetail?.version ?? ""
                        font.pointSize: Appearance.font.size.normal
                        color: Colours.palette.m3outline
                        anchors.baseline: parent.children[0]?.baseline
                    }
                }

                Row {
                    spacing: Appearance.spacing.small

                    // Repo badge
                    StyledRect {
                        visible: (Packages.selectedDetail?.repo ?? "") !== ""
                        color: {
                            const d = Packages.selectedDetail;
                            if (!d) return "transparent";
                            if (d.installed) return Qt.alpha(Colours.palette.m3primary, 0.15);
                            if (d.isAur) return Qt.alpha(Colours.palette.m3tertiary, 0.15);
                            return Colours.palette.m3surfaceContainerHighest;
                        }
                        radius: Appearance.rounding.full
                        implicitWidth: repoText.implicitWidth + Appearance.padding.normal * 2
                        implicitHeight: repoText.implicitHeight + Appearance.padding.small * 2

                        StyledText {
                            id: repoText
                            anchors.centerIn: parent
                            text: Packages.selectedDetail?.repo ?? ""
                            font.pointSize: Appearance.font.size.small
                            font.weight: Font.Medium
                            color: {
                                const d = Packages.selectedDetail;
                                if (!d) return Colours.palette.m3onSurfaceVariant;
                                if (d.installed) return Colours.palette.m3primary;
                                if (d.isAur) return Colours.palette.m3tertiary;
                                return Colours.palette.m3onSurfaceVariant;
                            }
                        }
                    }

                    // Installed indicator
                    Row {
                        visible: Packages.selectedDetail?.installed ?? false
                        spacing: 2
                        anchors.verticalCenter: parent.verticalCenter

                        MaterialIcon {
                            text: "check_circle"
                            font.pointSize: Appearance.font.size.small
                            color: Colours.palette.m3primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: qsTr("Installed")
                            font.pointSize: Appearance.font.size.small
                            color: Colours.palette.m3primary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }
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
            height: Math.min(
                contentHeight,
                root.maxHeight - detailHeader.implicitHeight - root.padding * 3
            )
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

            height: Math.min(
                contentHeight,
                (Config.packages.sizes.itemHeight + spacing) * Config.packages.maxShown - spacing,
                root.maxHeight - searchWrapper.implicitHeight - root.padding * 3
            )

            onModelChanged: currentIndex = 0

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
