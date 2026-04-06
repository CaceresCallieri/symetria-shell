pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.services

/// Ethernet network management: interface detection, connecting, disconnecting,
/// and device detail retrieval.
///
/// Delegates command execution to NmcliCore.executeCommand().
Singleton {
    id: root

    // --- Ethernet state ---
    property var ethernetInterfaces: []
    property list<var> ethernetDevices: []
    readonly property var activeEthernet: ethernetDevices.find(d => d.connected) ?? null
    property var ethernetDeviceDetails: null

    // --- Interface queries ---

    function getEthernetInterfaces(callback: var): void {
        NmcliCore.executeCommand(["-t", "-f", NmcliCore.deviceStatusFields, NmcliCore.nmcliCommandDevice, "status"], result => {
            const interfaces = NmcliCore.parseDeviceStatusOutput(result.output, NmcliCore.deviceTypeEthernet);
            const devices = [];

            for (const iface of interfaces) {
                const connected = NmcliCore.isConnectedState(iface.state);

                devices.push({
                    interface: iface.device,
                    type: iface.type,
                    state: iface.state,
                    connection: iface.connection,
                    connected: connected,
                    ipAddress: "",
                    gateway: "",
                    dns: [],
                    subnet: "",
                    macAddress: "",
                    speed: ""
                });
            }

            root.ethernetInterfaces = interfaces;
            root.ethernetDevices = devices;
            if (callback)
                callback(interfaces);
        });
    }

    // --- Connection operations ---

    function connectEthernet(connectionName: string, interfaceName: string, callback: var): void {
        if (connectionName && connectionName.length > 0) {
            NmcliCore.executeCommand([NmcliCore.nmcliCommandConnection, "up", connectionName], result => {
                if (result.success) {
                    Qt.callLater(() => {
                        getEthernetInterfaces(() => {});
                        if (interfaceName && interfaceName.length > 0) {
                            Qt.callLater(() => {
                                getEthernetDeviceDetails(interfaceName, () => {});
                            }, 1000);
                        }
                    }, 500);
                }
                if (callback)
                    callback(result);
            });
        } else if (interfaceName && interfaceName.length > 0) {
            NmcliCore.executeCommand([NmcliCore.nmcliCommandDevice, "connect", interfaceName], result => {
                if (result.success) {
                    Qt.callLater(() => {
                        getEthernetInterfaces(() => {});
                        Qt.callLater(() => {
                            getEthernetDeviceDetails(interfaceName, () => {});
                        }, 1000);
                    }, 500);
                }
                if (callback)
                    callback(result);
            });
        } else {
            if (callback)
                callback({
                    success: false,
                    output: "",
                    error: "No connection name or interface specified",
                    exitCode: -1
                });
        }
    }

    function disconnectEthernet(connectionName: string, callback: var): void {
        if (!connectionName || connectionName.length === 0) {
            if (callback)
                callback({
                    success: false,
                    output: "",
                    error: "No connection name specified",
                    exitCode: -1
                });
            return;
        }

        NmcliCore.executeCommand([NmcliCore.nmcliCommandConnection, "down", connectionName], result => {
            if (result.success) {
                root.ethernetDeviceDetails = null;
                Qt.callLater(() => {
                    getEthernetInterfaces(() => {});
                }, 500);
            }
            if (callback)
                callback(result);
        });
    }

    // --- Device details ---

    function getEthernetDeviceDetails(interfaceName: string, callback: var): void {
        if (!interfaceName || interfaceName.length === 0) {
            const activeInterface = root.ethernetInterfaces.find(iface => {
                return NmcliCore.isConnectedState(iface.state);
            });
            if (activeInterface && activeInterface.device) {
                interfaceName = activeInterface.device;
            } else {
                if (callback)
                    callback(null);
                return;
            }
        }

        NmcliCore.executeCommand([NmcliCore.nmcliCommandDevice, "show", interfaceName], result => {
            if (!result.success || !result.output) {
                root.ethernetDeviceDetails = null;
                if (callback)
                    callback(null);
                return;
            }

            const details = NmcliCore.parseDeviceDetails(result.output, true);
            root.ethernetDeviceDetails = details;
            if (callback)
                callback(details);
        });
    }

    // --- Initialization ---

    Component.onCompleted: {
        getEthernetInterfaces(() => {});

        Qt.callLater(() => {
            if (root.ethernetInterfaces.length > 0) {
                const activeEth = root.ethernetInterfaces.find(iface => {
                    return NmcliCore.isConnectedState(iface.state);
                });
                if (activeEth && activeEth.device) {
                    getEthernetDeviceDetails(activeEth.device, () => {});
                }
            }
        }, 2000);
    }
}
