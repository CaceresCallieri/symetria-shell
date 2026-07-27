pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.services

Singleton {
    id: root

    Component.onCompleted: {
        // Trigger ethernet device detection after initialization
        Qt.callLater(() => {
            getEthernetDevices();
        });
        // Load saved connections on startup
        NmcliWifi.loadSavedConnections(() => {
            root.savedConnections = NmcliWifi.savedConnections;
            root.savedConnectionSsids = NmcliWifi.savedConnectionSsids;
        });
        // Get initial WiFi status
        NmcliWifi.getWifiStatus((enabled) => {
            root.wifiEnabled = enabled;
        });
        // Sync networks from NmcliWifi on startup
        Qt.callLater(() => {
            syncNetworksFromNmcli();
        }, 100);
    }

    readonly property list<AccessPoint> networks: []
    readonly property AccessPoint active: networks.find(n => n.active) ?? null
    property bool wifiEnabled: true
    readonly property bool scanning: NmcliWifi.scanning

    property list<var> ethernetDevices: []
    // intentional var: nullable result from .find() over heterogeneous JS device objects
    readonly property var activeEthernet: ethernetDevices.find(d => d.connected) ?? null
    property int ethernetDeviceCount: 0
    property bool ethernetProcessRunning: false
    // intentional var: nullable JS object from nmcli device-details parser
    property var ethernetDeviceDetails: null
    // intentional var: nullable JS object from nmcli wireless-details parser
    property var wirelessDeviceDetails: null

    function enableWifi(enabled: bool): void {
        NmcliWifi.enableWifi(enabled, (result) => {
            if (result.success) {
                root.getWifiStatus();
                NmcliWifi.getNetworks(() => {
                    syncNetworksFromNmcli();
                });
            }
        });
    }

    function toggleWifi(): void {
        NmcliWifi.toggleWifi((result) => {
            if (result.success) {
                root.getWifiStatus();
                NmcliWifi.getNetworks(() => {
                    syncNetworksFromNmcli();
                });
            }
        });
    }

    function rescanWifi(): void {
        NmcliWifi.rescanWifi();
    }

    // intentional var: nullable JS object with mixed types ({ ssid: string, bssid: string, callback: function })
    property var pendingConnection: null
    signal connectionFailed(string ssid)

    function connectToNetwork(ssid: string, password: string, bssid: string, callback: var): void {
        // Set up pending connection tracking if callback provided
        if (callback) {
            const hasBssid = bssid !== undefined && bssid !== null && bssid.length > 0;
            root.pendingConnection = { ssid: ssid, bssid: hasBssid ? bssid : "", callback: callback };
        }
        
        NmcliWifi.connectToNetwork(ssid, password, bssid, (result) => {
            if (result && result.success) {
                // Connection successful
                if (callback) callback(result);
                root.pendingConnection = null;
            } else if (result && result.needsPassword) {
                // Password needed - callback will handle showing dialog
                if (callback) callback(result);
            } else {
                // Connection failed
                if (result && result.error) {
                    root.connectionFailed(ssid);
                }
                if (callback) callback(result);
                root.pendingConnection = null;
            }
        });
    }

    function connectToNetworkWithPasswordCheck(ssid: string, isSecure: bool, callback: var, bssid: string): void {
        // Set up pending connection tracking
        const hasBssid = bssid !== undefined && bssid !== null && bssid.length > 0;
        root.pendingConnection = { ssid: ssid, bssid: hasBssid ? bssid : "", callback: callback };
        
        NmcliWifi.connectToNetworkWithPasswordCheck(ssid, isSecure, (result) => {
            if (result && result.success) {
                // Connection successful
                if (callback) callback(result);
                root.pendingConnection = null;
            } else if (result && result.needsPassword) {
                // Password needed - callback will handle showing dialog
                if (callback) callback(result);
            } else {
                // Connection failed
                if (result && result.error) {
                    root.connectionFailed(ssid);
                }
                if (callback) callback(result);
                root.pendingConnection = null;
            }
        }, bssid);
    }

    function disconnectFromNetwork(ssid: string): void {
        // Try to disconnect - use connection name if available, otherwise use device
        NmcliWifi.disconnectFromNetwork(ssid);
        // Refresh network list after disconnection
        Qt.callLater(() => {
            NmcliWifi.getNetworks(() => {
                syncNetworksFromNmcli();
            });
        }, 500);
    }

    function forgetNetwork(ssid: string): void {
        // Delete the connection profile for this network
        // This will remove the saved password and connection settings
        NmcliWifi.forgetNetwork(ssid, (result) => {
            if (result.success) {
                // Refresh network list after deletion
                Qt.callLater(() => {
                    NmcliWifi.getNetworks(() => {
                        syncNetworksFromNmcli();
                    });
                }, 500);
            }
        });
    }


    property list<string> savedConnections: []
    property list<string> savedConnectionSsids: []

    // Sync saved connections from NmcliWifi when they're updated
    Connections {
        target: NmcliWifi
        function onSavedConnectionsChanged() {
            root.savedConnections = NmcliWifi.savedConnections;
        }
        function onSavedConnectionSsidsChanged() {
            root.savedConnectionSsids = NmcliWifi.savedConnectionSsids;
        }
    }

    function syncNetworksFromNmcli(): void {
        const rNetworks = root.networks;
        const nNetworks = NmcliWifi.networks;

        // Build a map of existing networks by key
        const existingMap = new Map();
        for (const rn of rNetworks) {
            const key = `${rn.frequency}:${rn.ssid}:${rn.bssid}`;
            existingMap.set(key, rn);
        }

        // Build result array in one pass, reusing existing objects where possible
        const result = [];
        const keptKeys = new Set();
        for (const nn of nNetworks) {
            const key = `${nn.frequency}:${nn.ssid}:${nn.bssid}`;
            const existing = existingMap.get(key);
            if (existing) {
                // Update existing network's lastIpcObject
                existing.lastIpcObject = nn.lastIpcObject;
                result.push(existing);
            } else {
                // Create new AccessPoint from NmcliWifi's data
                result.push(apComp.createObject(root, {
                    lastIpcObject: nn.lastIpcObject
                }));
            }
            keptKeys.add(key);
        }

        // Destroy removed networks after building the new list
        for (const [key, network] of existingMap) {
            if (!keptKeys.has(key)) {
                network.destroy();
            }
        }

        // Single assignment — O(1) binding trigger
        root.networks = result;
    }

    component AccessPoint: QtObject {
        // intentional var: heterogeneous JS object from nmcli network scan data
        required property var lastIpcObject
        readonly property string ssid: lastIpcObject.ssid
        readonly property string bssid: lastIpcObject.bssid
        readonly property int strength: lastIpcObject.strength
        readonly property int frequency: lastIpcObject.frequency
        readonly property bool active: lastIpcObject.active
        readonly property string security: lastIpcObject.security
        readonly property bool isSecure: security.length > 0
    }

    Component {
        id: apComp
        AccessPoint {}
    }

    function hasSavedProfile(ssid: string): bool {
        // Use NmcliWifi.hasSavedProfile which has the same logic
        return NmcliWifi.hasSavedProfile(ssid);
    }

    function getWifiStatus(): void {
        NmcliWifi.getWifiStatus((enabled) => {
            root.wifiEnabled = enabled;
        });
    }

    function getEthernetDevices(): void {
        root.ethernetProcessRunning = true;
        NmcliEthernet.getEthernetInterfaces((interfaces) => {
            root.ethernetDevices = NmcliEthernet.ethernetDevices;
            root.ethernetDeviceCount = NmcliEthernet.ethernetDevices.length;
            root.ethernetProcessRunning = false;
        });
    }


    function connectEthernet(connectionName: string, interfaceName: string): void {
        NmcliEthernet.connectEthernet(connectionName, interfaceName, (result) => {
            if (result.success) {
                getEthernetDevices();
                // Refresh device details after connection
                Qt.callLater(() => {
                    const activeDevice = root.ethernetDevices.find(function(d) { return d.connected; });
                    if (activeDevice && activeDevice.interface) {
                        updateEthernetDeviceDetails(activeDevice.interface);
                    }
                }, 1000);
            }
        });
    }

    function disconnectEthernet(connectionName: string): void {
        NmcliEthernet.disconnectEthernet(connectionName, (result) => {
            if (result.success) {
                getEthernetDevices();
                // Clear device details after disconnection
                Qt.callLater(() => {
                    root.ethernetDeviceDetails = null;
                });
            }
        });
    }

    function updateEthernetDeviceDetails(interfaceName: string): void {
        NmcliEthernet.getEthernetDeviceDetails(interfaceName, (details) => {
            root.ethernetDeviceDetails = details;
        });
    }

    function updateWirelessDeviceDetails(): void {
        // Find the wireless interface by looking for wifi devices
        // Pass empty string to let NmcliWifi find the active interface automatically
        NmcliWifi.getWirelessDeviceDetails("", (details) => {
            root.wirelessDeviceDetails = details;
        });
    }

    Process {
        running: true
        command: ["nmcli", "m"]
        stdout: SplitParser {
            onRead: {
                NmcliWifi.getNetworks(() => {
                    syncNetworksFromNmcli();
                });
                getEthernetDevices();
            }
        }
    }

}
