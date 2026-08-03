pragma ComponentBehavior: Bound

import ".."
import "../components"
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

DeviceList {
    id: root

    required property Session session

    title: qsTr("Devices (%1)").arg(NmcliEthernet.ethernetDevices.length)
    description: qsTr("All available ethernet devices")
    activeItem: session.ethernet.active

    model: NmcliEthernet.ethernetDevices

    headerComponent: Component {
        RowLayout {
            spacing: Appearance.spacing.smaller

            StyledText {
                text: qsTr("Settings")
                font.pointSize: Appearance.font.size.large
                font.weight: 500
            }

            Item {
                Layout.fillWidth: true
            }

            ToggleButton {
                toggled: !root.session.ethernet.active
                icon: "settings"
                accent: "Primary"
                iconSize: Appearance.font.size.normal
                horizontalPadding: Appearance.padding.normal
                verticalPadding: Appearance.padding.smaller

                onClicked: {
                    if (root.session.ethernet.active)
                        root.session.ethernet.active = null;
                    else {
                        root.session.ethernet.active = root.view.model.get(0)?.modelData ?? null;
                    }
                }
            }
        }
    }

    delegate: Component {
        StyledRect {
            id: ethernetItem

            required property var modelData // intentional var: heterogeneous JS object from NmcliEthernet.ethernetDevices model
            readonly property bool isActive: root.activeItem && modelData && root.activeItem.interface === modelData.interface

            width: ListView.view ? ListView.view.width : undefined
            implicitHeight: rowLayout.implicitHeight + Appearance.padding.normal * 2

            readonly property var activePill: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.strong) // intentional var: heterogeneous JS { background, border }

            color: ethernetItem.isActive ? activePill.background : "transparent"
            border.color: ethernetItem.isActive ? activePill.border : "transparent"
            border.width: ethernetItem.isActive ? 1 : 0
            radius: Appearance.rounding.normal

            StateLayer {
                id: stateLayer

                function onClicked(): void {
                    root.session.ethernet.active = modelData;
                }
            }

            RowLayout {
                id: rowLayout

                anchors.fill: parent
                anchors.margins: Appearance.padding.normal

                spacing: Appearance.spacing.normal

                StyledRect {
                    implicitWidth: implicitHeight
                    implicitHeight: icon.implicitHeight + Appearance.padding.normal * 2

                    radius: Appearance.rounding.normal
                    color: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, modelData.connected ? Colours.glass.veryStrong : Colours.glass.subtle).background

                    StyledRect {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Qt.alpha(Colours.palette.m3onSurface, stateLayer.pressed ? 0.1 : stateLayer.containsMouse ? 0.08 : 0)
                    }

                    MaterialIcon {
                        id: icon

                        anchors.centerIn: parent
                        text: "cable"
                        font.pointSize: Appearance.font.size.large
                        fill: modelData.connected ? 1 : 0
                        color: Colours.palette.m3onSurface

                        Behavior on fill {
                            Anim {}
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true

                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: modelData.interface || qsTr("Unknown")
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.spacing.smaller

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.connected ? qsTr("Connected") : qsTr("Disconnected")
                            color: modelData.connected ? Colours.palette.m3primary : Colours.palette.m3outline
                            font.pointSize: Appearance.font.size.small
                            font.weight: modelData.connected ? 500 : 400
                            elide: Text.ElideRight
                        }
                    }
                }

                ConnectToggleButton {
                    id: connectBtn

                    connected: modelData.connected

                    onClicked: {
                        if (modelData.connected && modelData.connection) {
                            NmcliEthernet.disconnectEthernet(modelData.connection, () => {});
                        } else {
                            NmcliEthernet.connectEthernet(modelData.connection || "", modelData.interface || "", () => {});
                        }
                    }
                }
            }
        }
    }

    onItemSelected: function(item) {
        session.ethernet.active = item;
    }
}
