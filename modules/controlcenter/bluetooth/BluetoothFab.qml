pragma ComponentBehavior: Bound

import ".."
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.config
import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts

/// Floating Action Button with expandable quick-action menu for bluetooth device details.
/// Provides trust/block/pair/connect actions via animated pop-up menu items.
/// Positioned at the bottom-right of the parent flickable's visible viewport.
Item {
    id: root

    required property Session session
    required property BluetoothDevice device

    /// Flickable scroll and viewport dimensions for sticky positioning.
    required property real scrollX
    required property real scrollY
    required property real viewWidth
    required property real viewHeight

    // ── Helpers ──────────────────────────────────────────────────

    function menuItemLabel(device: QtObject, name: string): string {
        if (!device || !device[`${name}ed`])
            return name;
        return (name === "connect" ? "dis" : "un") + name;
    }

    // ── Menu items ───────────────────────────────────────────────

    ColumnLayout {
        anchors.right: fabRoot.right
        anchors.bottom: fabRoot.top
        anchors.bottomMargin: Appearance.padding.normal

        Repeater {
            id: fabMenu

            model: ListModel {
                ListElement {
                    name: "trust"
                    icon: "handshake"
                }
                ListElement {
                    name: "block"
                    icon: "block"
                }
                ListElement {
                    name: "pair"
                    icon: "missing_controller"
                }
                ListElement {
                    name: "connect"
                    icon: "bluetooth_connected"
                }
            }

            StyledClippingRect {
                id: fabMenuItem

                required property var modelData // intentional var: ListModel element { name, icon } from fab menu
                required property int index

                Layout.alignment: Qt.AlignRight

                implicitHeight: fabMenuItemInner.implicitHeight + Appearance.padding.larger * 2

                radius: Appearance.rounding.full
                color: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle).background

                opacity: 0

                states: State {
                    name: "visible"
                    when: root.session.bt.fabMenuOpen

                    PropertyChanges {
                        fabMenuItem.implicitWidth: fabMenuItemInner.implicitWidth + Appearance.padding.large * 2
                        fabMenuItem.opacity: 1
                        fabMenuItemInner.opacity: 1
                    }
                }

                transitions: [
                    Transition {
                        to: "visible"

                        SequentialAnimation {
                            PauseAnimation {
                                duration: (fabMenu.count - 1 - fabMenuItem.index) * Appearance.anim.durations.small / 8
                            }
                            ParallelAnimation {
                                Anim {
                                    property: "implicitWidth"
                                    duration: Appearance.anim.durations.expressiveFastSpatial
                                    easing.bezierCurve: Appearance.anim.curves.expressiveFastSpatial
                                }
                                Anim {
                                    property: "opacity"
                                    duration: Appearance.anim.durations.small
                                }
                            }
                        }
                    },
                    Transition {
                        from: "visible"

                        SequentialAnimation {
                            PauseAnimation {
                                duration: fabMenuItem.index * Appearance.anim.durations.small / 8
                            }
                            ParallelAnimation {
                                Anim {
                                    property: "implicitWidth"
                                    duration: Appearance.anim.durations.expressiveFastSpatial
                                    easing.bezierCurve: Appearance.anim.curves.expressiveFastSpatial
                                }
                                Anim {
                                    property: "opacity"
                                    duration: Appearance.anim.durations.small
                                }
                            }
                        }
                    }
                ]

                StateLayer {
                    function onClicked(): void {
                        root.session.bt.fabMenuOpen = false;

                        const name = fabMenuItem.modelData.name;
                        if (name !== "pair")
                            root.device[`${name}ed`] = !root.device[`${name}ed`];
                        else if (root.device.paired)
                            root.device.forget();
                        else
                            root.device.pair();
                    }
                }

                RowLayout {
                    id: fabMenuItemInner

                    anchors.centerIn: parent
                    spacing: Appearance.spacing.normal
                    opacity: 0

                    MaterialIcon {
                        text: fabMenuItem.modelData.icon
                        color: Colours.palette.m3onSurface
                        fill: 1
                    }

                    StyledText {
                        animate: true
                        text: root.menuItemLabel(root.device, fabMenuItem.modelData.name)
                        color: Colours.palette.m3onSurface
                        font.capitalization: Font.Capitalize
                        Layout.preferredWidth: implicitWidth

                        Behavior on Layout.preferredWidth {
                            Anim {
                                duration: Appearance.anim.durations.small
                            }
                        }
                    }
                }
            }
        }
    }

    // ── FAB button ───────────────────────────────────────────────

    Item {
        id: fabRoot

        x: root.scrollX + root.viewWidth - width
        y: root.scrollY + root.viewHeight - height
        width: 64
        height: 64
        z: 10000

        StyledRect {
            id: fabBg

            anchors.right: parent.right
            anchors.top: parent.top

            implicitWidth: 64
            implicitHeight: 64

            radius: Appearance.rounding.normal
            color: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, root.session.bt.fabMenuOpen ? Colours.glass.veryStrong : Colours.glass.subtle).background

            states: State {
                name: "expanded"
                when: root.session.bt.fabMenuOpen

                PropertyChanges {
                    fabBg.implicitWidth: 48
                    fabBg.implicitHeight: 48
                    fabBg.radius: 48 / 2
                    fab.font.pointSize: Appearance.font.size.larger
                }
            }

            transitions: Transition {
                Anim {
                    properties: "implicitWidth,implicitHeight"
                    duration: Appearance.anim.durations.expressiveFastSpatial
                    easing.bezierCurve: Appearance.anim.curves.expressiveFastSpatial
                }
                Anim {
                    properties: "radius,font.pointSize"
                }
            }

            Elevation {
                anchors.fill: parent
                radius: parent.radius
                z: -1
                level: fabState.containsMouse && !fabState.pressed ? 4 : 3
            }

            StateLayer {
                id: fabState

                color: Colours.palette.m3onSurface

                function onClicked(): void {
                    root.session.bt.fabMenuOpen = !root.session.bt.fabMenuOpen;
                }
            }

            MaterialIcon {
                id: fab

                anchors.centerIn: parent
                animate: true
                text: root.session.bt.fabMenuOpen ? "close" : "settings"
                color: Colours.palette.m3onSurface
                font.pointSize: Appearance.font.size.large
                fill: 1
            }
        }
    }
}
