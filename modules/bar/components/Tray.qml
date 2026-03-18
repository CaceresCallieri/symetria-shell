pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell.Services.SystemTray
import QtQuick

StyledRect {
    id: root

    // Popout interface: trayContainer is the Row, trayItems is the Repeater
    readonly property alias trayContainer: layout
    readonly property alias trayItems: items
    readonly property alias expandIcon: expandIcon

    readonly property int pillPadding: Appearance.spacing.large
    readonly property int spacing: Appearance.spacing.small

    property bool expanded

    // Glassmorphism styling (subtle intensity for background containers,
    // matching OccupiedBg and WorkspaceAppIcons grouped pill styling)
    readonly property var glassStyle: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)

    // Width calculation: In non-compact mode, Row's implicitWidth includes
    // leftPadding + rightPadding. In compact mode, we manually calculate
    // based on expanded state and add padding for the expand icon area.
    readonly property real nonAnimWidth: {
        if (!Config.bar.tray.compact)
            return layout.implicitWidth;
        return (expanded ? expandIcon.implicitWidth + layout.implicitWidth + spacing : expandIcon.implicitWidth) + pillPadding * 2;
    }

    clip: true
    visible: width > 0

    implicitHeight: Config.bar.sizes.innerWidth
    implicitWidth: nonAnimWidth

    color: items.count > 0 ? glassStyle.background : "transparent"
    radius: Appearance.rounding.full
    border.width: items.count > 0 ? 1 : 0
    border.color: glassStyle.border

    Row {
        id: layout

        anchors.centerIn: parent
        spacing: Appearance.spacing.small

        // Row has built-in padding properties (unlike RowLayout)
        leftPadding: root.pillPadding
        rightPadding: root.pillPadding

        opacity: root.expanded || !Config.bar.tray.compact ? 1 : 0

        add: Transition {
            Anim {
                properties: "scale"
                from: 0
                to: 1
                easing.bezierCurve: Appearance.anim.curves.standardDecel
            }
        }

        move: Transition {
            Anim {
                properties: "scale"
                to: 1
                easing.bezierCurve: Appearance.anim.curves.standardDecel
            }
            Anim {
                properties: "x,y"
            }
        }

        Repeater {
            id: items

            model: SystemTray.items

            TrayItem {}
        }

        Behavior on opacity {
            Anim {}
        }
    }

    Loader {
        id: expandIcon

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right

        active: Config.bar.tray.compact

        sourceComponent: Item {
            implicitHeight: expandIconInner.implicitHeight
            implicitWidth: expandIconInner.implicitWidth - Appearance.padding.small * 2

            MaterialIcon {
                id: expandIconInner

                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Appearance.padding.small
                text: "expand_less"
                font.pointSize: Appearance.font.size.large
                rotation: root.expanded ? 90 : -90

                Behavior on rotation {
                    Anim {}
                }

                Behavior on anchors.rightMargin {
                    Anim {}
                }
            }
        }
    }

    Behavior on implicitWidth {
        Anim {
            duration: Appearance.anim.durations.expressiveDefaultSpatial
            easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
        }
    }
}
