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
/// Layout (top-hanging, search at top, results below):
/// - Search bar with debounced input
/// - Loading indicator OR result list OR empty state
Item {
    id: root

    required property PersistentProperties visibilities
    required property real maxHeight

    readonly property int padding: Appearance.padding.large

    function focusSearch(): void {
        search.forceActiveFocus();
    }

    FocusManager {
        active: root.visibilities.packages
        target: search
        onClose: () => {
            search.text = "";
            Packages.cancelSearch();
            Packages.hasSearched = false;
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
        let h = searchWrapper.implicitHeight + padding * 2;
        if (resultSection.visible)
            h += resultSection.implicitHeight + padding;
        return Math.min(root.maxHeight, h);
    }

    // ===== Search bar (top) =====
    StyledRect {
        id: searchWrapper

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
                // Enter copies install command for highlighted item
                if (resultList.count > 0 && resultList.currentIndex >= 0) {
                    const entry = Packages.results[resultList.currentIndex];
                    if (entry)
                        Packages.copyInstallCommand(entry.name);
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

            Keys.onEscapePressed: root.visibilities.packages = false
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

    // Debug: track visibility state changes
    Connections {
        target: Packages

        function onSearchingChanged(): void {
            console.log("[Packages UI] searching:", Packages.searching, "results:", Packages.results.length, "hasSearched:", Packages.hasSearched);
        }

        function onResultsChanged(): void {
            console.log("[Packages UI] results changed:", Packages.results.length, "searching:", Packages.searching,
                "resultList.visible:", resultList.visible, "loadingState.visible:", loadingState.visible);
        }
    }

    // ===== Result section (below search) =====
    Item {
        id: resultSection

        visible: Packages.searching || Packages.hasSearched

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
