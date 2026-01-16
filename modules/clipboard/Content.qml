pragma ComponentBehavior: Bound

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

    implicitWidth: Config.clipboard.sizes.itemWidth + padding * 2
    implicitHeight: listWrapper.height + header.height + padding * 2

    // Activate clipboard service when drawer is open
    Binding {
        target: Clipboard
        property: "refCount"
        value: Clipboard.refCount + 1
        when: root.visibilities.clipboard
        restoreMode: Binding.RestoreValue
    }

    // List wrapper (above header, like launcher)
    Item {
        id: listWrapper

        implicitWidth: list.width
        implicitHeight: Clipboard.entries.length > 0 ? list.height + root.padding : empty.height

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: header.top
        anchors.bottomMargin: root.padding

        StyledListView {
            id: list

            visible: Clipboard.entries.length > 0
            model: Clipboard.entries
            width: Config.clipboard.sizes.itemWidth
            height: Math.min(contentHeight, root.maxHeight - header.height - root.padding * 3)
            clip: true
            spacing: Appearance.spacing.small
            topMargin: Appearance.spacing.normal
            orientation: Qt.Vertical
            reuseItems: true
            implicitHeight: (Config.clipboard.sizes.itemHeight + spacing) * Math.min(Config.clipboard.maxShown, count) - spacing

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

            visible: Clipboard.entries.length === 0
            opacity: visible ? 1 : 0
            scale: visible ? 1 : 0.5

            spacing: Appearance.spacing.normal
            padding: Appearance.padding.large

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            MaterialIcon {
                text: "content_paste_off"
                color: Colours.palette.m3onSurfaceVariant
                font.pointSize: Appearance.font.size.extraLarge

                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    text: qsTr("No clipboard history")
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Appearance.font.size.larger
                    font.weight: 500
                }

                StyledText {
                    text: qsTr("Copy something to get started")
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

    // Header bar at bottom (like launcher's search bar)
    StyledRect {
        id: header

        color: Colours.layer(Colours.palette.m3surfaceContainer, 2)
        radius: Appearance.rounding.full

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.padding

        implicitHeight: headerContent.implicitHeight + Appearance.padding.larger * 2

        RowLayout {
            id: headerContent

            anchors.fill: parent
            anchors.leftMargin: root.padding
            anchors.rightMargin: root.padding
            spacing: Appearance.spacing.normal

            MaterialIcon {
                text: "content_paste"
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                text: qsTr("Clipboard History")
                color: Colours.palette.m3onSurfaceVariant
                Layout.fillWidth: true
            }

            // Clear all button (double-click to confirm)
            Item {
                implicitWidth: clearIcon.implicitWidth
                implicitHeight: clearIcon.implicitHeight
                visible: Clipboard.entries.length > 0

                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.confirmClear) {
                            Clipboard.clear();
                            root.confirmClear = false;
                        } else {
                            root.confirmClear = true;
                            confirmTimer.restart();
                        }
                    }
                }

                MaterialIcon {
                    id: clearIcon
                    text: root.confirmClear ? "warning" : "delete_sweep"
                    color: root.confirmClear ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant

                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.anim.durations.small
                        }
                    }
                }
            }
        }
    }

    // Confirmation timeout for clear all
    Timer {
        id: confirmTimer
        interval: 2000
        onTriggered: root.confirmClear = false
    }

    // Keyboard navigation
    Keys.onEscapePressed: root.visibilities.clipboard = false

    Keys.onUpPressed: {
        if (list.currentIndex > 0)
            list.currentIndex--;
    }

    Keys.onDownPressed: {
        if (list.currentIndex < list.count - 1)
            list.currentIndex++;
    }

    Keys.onReturnPressed: {
        const item = list.currentItem;
        if (item && item.entry) {
            Clipboard.restore(item.entry.id);
            root.visibilities.clipboard = false;
        }
    }

    Keys.onDeletePressed: {
        const item = list.currentItem;
        if (item && item.entry)
            Clipboard.remove(item.entry.id);
    }

    Component.onCompleted: {
        forceActiveFocus();
        Clipboard.refresh();
    }

    Connections {
        target: root.visibilities

        function onClipboardChanged(): void {
            if (root.visibilities.clipboard) {
                root.forceActiveFocus();
                Clipboard.refresh();
                list.currentIndex = 0;
            } else {
                // Reset confirmation state when drawer closes
                root.confirmClear = false;
            }
        }
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
