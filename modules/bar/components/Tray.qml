pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell.Services.SystemTray
import QtQuick

Item {
    id: root

    // Popout interface: trayContainer is the Row, trayItems is the Repeater
    readonly property alias trayContainer: layout
    readonly property alias trayItems: items
    readonly property alias expandIcon: expandIcon

    readonly property int pillPadding: Appearance.spacing.large
    readonly property int spacing: Appearance.spacing.small

    property bool expanded

    // Width calculation: In non-compact mode, Row's implicitWidth includes
    // leftPadding + rightPadding. In compact mode, we manually calculate
    // based on expanded state and add padding for the expand icon area.
    readonly property real nonAnimWidth: {
        if (!Config.bar.tray.compact)
            return layout.implicitWidth;
        return (expanded ? expandIcon.implicitWidth + layout.implicitWidth + spacing : expandIcon.implicitWidth) + pillPadding * 2;
    }

    visible: width > 0

    implicitHeight: Config.bar.sizes.innerWidth
    implicitWidth: nonAnimWidth

    // Shared pill background. Hidden when the tray is empty so the bar shows
    // no floating shadow/frame when there are no items. Borderless/transparent
    // state is handled by `visible` rather than fading `color` → "transparent"
    // because the pill's drop shadow must also disappear.
    PillSurface {
        anchors.fill: parent
        visible: items.count > 0
    }

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
