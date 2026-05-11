pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell
import Quickshell.Wayland
import QtQuick

/// One tile in the Window Overview grid.
///
/// Captures the repClient's surface via ScreencopyView (frozen snapshot, not live)
/// and preserves source aspect ratio inside the cell. Letter pill in the corner
/// shows the keyboard shortcut. Title strip is a known future improvement.
///
/// Tiles with empty label (overflow past 16 windows) still render but have no pill.
Item {
    id: root

    /// Tile model entry from WindowOverviewService.tiles:
    /// { isGroup, repClient, addr, label }
    // intentional var: plain JS object record from service
    required property var tileData

    /// Available cell space; tile letterboxes within while preserving aspect.
    required property real cellWidth
    required property real cellHeight

    implicitWidth: cellWidth
    implicitHeight: cellHeight

    readonly property real srcWidth: tileData?.repClient?.lastIpcObject?.size?.[0] ?? 1
    readonly property real srcHeight: tileData?.repClient?.lastIpcObject?.size?.[1] ?? 1
    readonly property real srcAspect: srcWidth / Math.max(1, srcHeight)
    readonly property real cellAspect: cellWidth / Math.max(1, cellHeight)

    // Aspect-preserving fit inside the cell.
    readonly property real fitWidth: srcAspect > cellAspect ? cellWidth : cellHeight * srcAspect
    readonly property real fitHeight: srcAspect > cellAspect ? cellWidth / srcAspect : cellHeight

    Rectangle {
        id: frame

        anchors.centerIn: parent
        width: root.fitWidth
        height: root.fitHeight

        color: Colours.palette.m3surfaceContainer
        radius: Appearance.rounding.normal
        clip: true

        ScreencopyView {
            id: capture

            anchors.fill: parent
            captureSource: root.tileData?.repClient?.wayland ?? null
            live: false

            // Fade in once the first frame lands. Masks the brief empty-frame
            // race between window-map and screencopy first-paint.
            opacity: hasContent ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 80
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Subtle border for tile separation against the dim scrim.
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: parent.radius
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
        }

        // Click-to-focus: works for every tile, including overflow tiles past
        // slot 16 that have no keyboard label.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: WindowOverviewService.activateAddr(root.tileData?.addr ?? "")
        }
    }

    // Letter pill — top-left corner of the tile frame.
    Rectangle {
        id: labelPill

        visible: (root.tileData?.label ?? "") !== ""

        anchors.left: frame.left
        anchors.top: frame.top
        anchors.leftMargin: Appearance.padding.normal
        anchors.topMargin: Appearance.padding.normal

        width: Math.max(height, labelText.implicitWidth + Appearance.padding.normal * 2)
        height: labelText.implicitHeight + Appearance.padding.small * 2
        radius: height / 2

        color: Colours.palette.m3primary

        StyledText {
            id: labelText

            anchors.centerIn: parent
            text: {
                const lbl = root.tileData?.label ?? "";
                // Render Enter/Return as a glyph; keeps the pill visually compact.
                return lbl === "Return" ? "↵" : lbl;
            }
            font.pointSize: Appearance.font.size.larger
            font.weight: Font.Bold
            color: Colours.palette.m3onPrimary
        }
    }
}
