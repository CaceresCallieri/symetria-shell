pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.utils
import qs.config
import Quickshell
import Quickshell.Widgets
import QtQuick

/// Minimal navigation hint positioned over one real Hyprland client rectangle.
Item {
    id: root

    required property var tileData
    required property ShellScreen screen

    readonly property var clientIpc: tileData?.repClient?.lastIpcObject
    readonly property real clientX: clientIpc?.at?.[0] ?? screen.x
    readonly property real clientY: clientIpc?.at?.[1] ?? screen.y
    readonly property real clientWidth: clientIpc?.size?.[0] ?? 0
    readonly property real clientHeight: clientIpc?.size?.[1] ?? 0
    readonly property bool compact: width < 210 || height < 150
    readonly property real iconSize: compact ? 28 : 36
    readonly property real maximumTitleWidth: Math.max(0, Math.min(260, width - iconSize - Appearance.spacing.normal - Appearance.padding.normal * 2))

    x: clientX - screen.x
    y: clientY - screen.y
    width: clientWidth
    height: clientHeight
    visible: width > 0 && height > 0

    // App identity stays against the top edge of the real window. Only the
    // title has a surface; the icon remains directly over client content.
    Row {
        id: identityRow

        anchors.top: parent.top
        anchors.topMargin: root.compact ? Appearance.padding.normal : Appearance.padding.large
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Appearance.spacing.normal

        IconImage {
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: root.iconSize
            source: Icons.resolveWindowIcon(root.clientIpc?.class ?? "", root.clientIpc?.title ?? "")
        }

        PillSurface {
            visible: root.maximumTitleWidth >= 64
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(root.maximumTitleWidth, titleText.implicitWidth + Appearance.padding.normal * 2)
            height: titleText.implicitHeight + Appearance.padding.small * 2

            StyledText {
                id: titleText

                anchors.fill: parent
                anchors.leftMargin: Appearance.padding.normal
                anchors.rightMargin: Appearance.padding.normal
                verticalAlignment: Text.AlignVCenter
                text: root.clientIpc?.title || root.clientIpc?.class || qsTr("Unknown window")
                color: Colours.palette.m3onSurface
                font.pointSize: Appearance.font.size.small
                elide: Text.ElideMiddle
                maximumLineCount: 1
            }
        }
    }

    // The key sits directly below the identity row and uses the shared display
    // surface. Theme.material changes its finish without local special cases.
    PillSurface {
        id: keyHint

        anchors.top: identityRow.bottom
        anchors.topMargin: root.compact ? Appearance.spacing.small : Appearance.spacing.normal
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.compact ? 48 : 62
        height: width
        visible: (root.tileData?.label ?? "") !== ""

        StyledText {
            anchors.centerIn: parent
            text: root.tileData?.label === "Return" ? "↵" : (root.tileData?.label ?? "")
            color: Colours.palette.m3onSurface
            font.pointSize: root.compact ? Appearance.font.size.normal : Appearance.font.size.larger
            font.weight: Font.Bold
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: WindowOverviewService.activateAddr(root.tileData?.addr ?? "")
    }
}
