pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.config
import qs.utils
import Quickshell
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property Item wrapper

    // Maximum list height before scrolling kicks in (~8 items at typical item height)
    property real maxNetworkListHeight: 350
    property string connectingToSsid: ""
    property string view: "wireless" // "wireless" or "ethernet"
    // intentional var: nullable JS object from network scan data ({ ssid, bssid, security, ... })
    property var passwordNetwork: null
    property bool showPasswordDialog: false

    implicitWidth: Config.bar.sizes.networkWidth
    implicitHeight: layout.implicitHeight + Appearance.padding.large * 2

    PillCard {
        anchors.fill: parent
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Appearance.padding.large
        anchors.rightMargin: Appearance.padding.large
        spacing: Appearance.spacing.small

        // Wireless section
        StyledText {
            visible: root.view === "wireless"
            Layout.preferredHeight: visible ? implicitHeight : 0
            text: qsTr("Wireless")
            font.weight: 500
        }

        Toggle {
            visible: root.view === "wireless"
            Layout.preferredHeight: visible ? implicitHeight : 0
            label: qsTr("Enabled")
            checked: NmcliWifi.wifiEnabled
            toggle.onToggled: NmcliWifi.enableWifi(checked)
        }

        StyledText {
            visible: root.view === "wireless"
            Layout.preferredHeight: visible ? implicitHeight : 0
            Layout.topMargin: visible ? Appearance.spacing.small : 0
            text: qsTr("%1 networks available").arg(NmcliWifi.networks.length)
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Appearance.font.size.small
        }

        StyledListView {
            id: networkList

            visible: root.view === "wireless"
            Layout.preferredHeight: root.view === "wireless" ? Math.min(contentHeight, root.maxNetworkListHeight) : 0
            Layout.fillWidth: true

            model: ScriptModel {
                values: [...NmcliWifi.networks].sort((a, b) => {
                    if (a.active !== b.active)
                        return b.active - a.active;
                    return b.strength - a.strength;
                })
            }
            clip: true
            spacing: Appearance.spacing.small

            delegate: RowLayout {
                id: networkItem

                required property NmcliWifi.AccessPoint modelData
                readonly property bool isConnecting: root.connectingToSsid === modelData.ssid
                readonly property bool loading: networkItem.isConnecting

                width: networkList.width
                spacing: Appearance.spacing.small

                MaterialIcon {
                    text: Icons.getNetworkIcon(networkItem.modelData.strength)
                    color: networkItem.modelData.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                }

                MaterialIcon {
                    visible: networkItem.modelData.isSecure
                    text: "lock"
                    font.pointSize: Appearance.font.size.small
                }

                StyledText {
                    Layout.leftMargin: Appearance.spacing.small / 2
                    Layout.rightMargin: Appearance.spacing.small / 2
                    Layout.fillWidth: true
                    text: networkItem.modelData.ssid
                    elide: Text.ElideRight
                    font.weight: networkItem.modelData.active ? 500 : 400
                    color: networkItem.modelData.active ? Colours.palette.m3primary : Colours.palette.m3onSurface
                }

                StyledRect {
                    implicitWidth: implicitHeight
                    implicitHeight: wirelessConnectIcon.implicitHeight + Appearance.padding.small

                    radius: Appearance.rounding.full
                    color: Qt.alpha(Colours.palette.m3primary, networkItem.modelData.active ? 1 : 0)

                    CircularIndicator {
                        anchors.fill: parent
                        running: networkItem.loading
                    }

                    StateLayer {
                        color: networkItem.modelData.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                        disabled: networkItem.loading || !NmcliWifi.wifiEnabled

                        function onClicked(): void {
                            if (networkItem.modelData.active) {
                                NmcliWifi.disconnectFromNetwork();
                            } else {
                                root.connectingToSsid = networkItem.modelData.ssid;
                                NetworkConnection.handleConnect(
                                    networkItem.modelData,
                                    null,
                                    (network) => {
                                        root.passwordNetwork = network;
                                        root.showPasswordDialog = true;
                                        root.wrapper.currentName = "wirelesspassword";
                                    }
                                );
                            }
                        }
                    }

                    MaterialIcon {
                        id: wirelessConnectIcon

                        anchors.centerIn: parent
                        animate: true
                        text: networkItem.modelData.active ? "link_off" : "link"
                        color: networkItem.modelData.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface

                        opacity: networkItem.loading ? 0 : 1

                        Behavior on opacity {
                            Anim {}
                        }
                    }
                }
            }

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: networkList
            }
        }

        // Always-raised rescan action pill. CircularIndicator overlays
        // the row when scanning so the spinner replaces the icon+label
        // in-place — same visual behavior as the prior StyledRect, just
        // wrapped in the shell's neumorphic depth recipe.
        PillToggleSurface {
            id: rescanPill

            visible: root.view === "wireless"
            Layout.preferredHeight: visible ? implicitHeight : 0
            Layout.topMargin: visible ? Appearance.spacing.small : 0
            Layout.fillWidth: true
            implicitHeight: rescanBtn.implicitHeight + Appearance.padding.small * 2
            active: false

            StateLayer {
                color: Colours.palette.m3onSurface
                disabled: NmcliWifi.scanning || !NmcliWifi.wifiEnabled

                function onClicked(): void {
                    NmcliWifi.rescanWifi();
                }
            }

            RowLayout {
                id: rescanBtn

                anchors.centerIn: parent
                spacing: Appearance.spacing.small
                opacity: NmcliWifi.scanning ? 0 : 1

                MaterialIcon {
                    id: scanIcon

                    Layout.topMargin: Math.round(fontInfo.pointSize * 0.0575)
                    animate: true
                    text: "wifi_find"
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.topMargin: -Math.round(scanIcon.fontInfo.pointSize * 0.0575)
                    text: qsTr("Rescan networks")
                    color: Colours.palette.m3onSurface
                }

                Behavior on opacity {
                    Anim {}
                }
            }

            CircularIndicator {
                anchors.centerIn: parent
                strokeWidth: Appearance.padding.small / 2
                bgColour: "transparent"
                implicitHeight: parent.implicitHeight - Appearance.padding.smaller * 2
                running: NmcliWifi.scanning
            }
        }

        // Ethernet section
        StyledText {
            visible: root.view === "ethernet"
            Layout.preferredHeight: visible ? implicitHeight : 0
            text: qsTr("Ethernet")
            font.weight: 500
        }

        StyledText {
            visible: root.view === "ethernet"
            Layout.preferredHeight: visible ? implicitHeight : 0
            Layout.topMargin: visible ? Appearance.spacing.small : 0
            text: qsTr("%1 devices available").arg(NmcliEthernet.ethernetDevices.length)
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Appearance.font.size.small
        }

        StyledListView {
            id: ethernetList

            visible: root.view === "ethernet"
            Layout.preferredHeight: root.view === "ethernet" ? Math.min(contentHeight, root.maxNetworkListHeight) : 0
            Layout.fillWidth: true

            model: ScriptModel {
                values: [...NmcliEthernet.ethernetDevices].sort((a, b) => {
                    if (a.connected !== b.connected)
                        return b.connected - a.connected;
                    return (a.interface || "").localeCompare(b.interface || "");
                })
            }
            clip: true
            spacing: Appearance.spacing.small

            delegate: RowLayout {
                id: ethernetItem

                // intentional var: heterogeneous JS object from NmcliEthernet device data
                required property var modelData
                // Ethernet connect is instantaneous — no async loading state
                readonly property bool loading: false

                width: ethernetList.width
                spacing: Appearance.spacing.small

                MaterialIcon {
                    text: "cable"
                    color: ethernetItem.modelData.connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                }

                StyledText {
                    Layout.leftMargin: Appearance.spacing.small / 2
                    Layout.rightMargin: Appearance.spacing.small / 2
                    Layout.fillWidth: true
                    text: ethernetItem.modelData.interface || qsTr("Unknown")
                    elide: Text.ElideRight
                    font.weight: ethernetItem.modelData.connected ? 500 : 400
                    color: ethernetItem.modelData.connected ? Colours.palette.m3primary : Colours.palette.m3onSurface
                }

                StyledRect {
                    implicitWidth: implicitHeight
                    implicitHeight: connectIcon.implicitHeight + Appearance.padding.small

                    radius: Appearance.rounding.full
                    color: Qt.alpha(Colours.palette.m3primary, ethernetItem.modelData.connected ? 1 : 0)

                    CircularIndicator {
                        anchors.fill: parent
                        running: ethernetItem.loading
                    }

                    StateLayer {
                        color: ethernetItem.modelData.connected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                        disabled: ethernetItem.loading

                        function onClicked(): void {
                            if (ethernetItem.modelData.connected && ethernetItem.modelData.connection) {
                                NmcliEthernet.disconnectEthernet(ethernetItem.modelData.connection, () => {});
                            } else {
                                NmcliEthernet.connectEthernet(ethernetItem.modelData.connection || "", ethernetItem.modelData.interface || "", () => {});
                            }
                        }
                    }

                    MaterialIcon {
                        id: connectIcon

                        anchors.centerIn: parent
                        animate: true
                        text: ethernetItem.modelData.connected ? "link_off" : "link"
                        color: ethernetItem.modelData.connected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface

                        opacity: ethernetItem.loading ? 0 : 1

                        Behavior on opacity {
                            Anim {}
                        }
                    }
                }
            }

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: ethernetList
            }
        }
    }

    Connections {
        target: NmcliWifi

        function onActiveChanged(): void {
            if (NmcliWifi.active && root.connectingToSsid === NmcliWifi.active.ssid) {
                root.connectingToSsid = "";
                // Close password dialog if we successfully connected
                if (root.showPasswordDialog && root.passwordNetwork && NmcliWifi.active.ssid === root.passwordNetwork.ssid) {
                    root.showPasswordDialog = false;
                    root.passwordNetwork = null;
                    if (root.wrapper.currentName === "wirelesspassword") {
                        root.wrapper.currentName = "network";
                    }
                }
            }
        }

        function onScanningChanged(): void {
            if (!NmcliWifi.scanning)
                scanIcon.rotation = 0;
        }
    }

    Connections {
        target: root.wrapper
        function onCurrentNameChanged(): void {
            // Clear password network when leaving password dialog
            if (root.wrapper.currentName !== "wirelesspassword" && root.showPasswordDialog) {
                root.showPasswordDialog = false;
                root.passwordNetwork = null;
            }
        }
    }

    component Toggle: RowLayout {
        required property string label
        property alias checked: toggle.checked
        property alias toggle: toggle

        Layout.fillWidth: true
        spacing: Appearance.spacing.normal

        StyledText {
            Layout.fillWidth: true
            text: parent.label
        }

        StyledSwitch {
            id: toggle
        }
    }
}
