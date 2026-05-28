pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.services

/// WiFi network management: scanning, connecting, disconnecting, saved profiles,
/// password handling, and connection state tracking.
///
/// Delegates command execution to NmcliCore.executeCommand().
Singleton {
    id: root

    // --- WiFi state ---
    property var wirelessInterfaces: []
    property bool wifiEnabled: true
    readonly property bool scanning: rescanProc.running
    readonly property list<AccessPoint> networks: []
    readonly property AccessPoint active: networks.find(n => n.active) ?? null
    property list<string> savedConnections: []
    property list<string> savedConnectionSsids: []
    property var wirelessDeviceDetails: null

    // --- Connection state ---
    property var wifiConnectionQueue: []
    property int currentSsidQueryIndex: 0
    property var pendingConnection: null
    signal connectionFailed(string ssid)

    // --- Password detection ---

    function detectPasswordRequired(error: string): bool {
        if (!error || error.length === 0) {
            return false;
        }

        const notSuccess = !error.includes("Connection activated") && !error.includes("successfully");
        const hasSecretKeyword = error.includes("Secrets were required")
            || error.includes("Secrets were required, but not provided")
            || error.includes("No secrets provided")
            || error.includes("802-11-wireless-security.psk")
            || error.includes("password for");
        const hasPasswordWord = error.includes("password") && notSuccess;
        const hasSecretsWord = error.includes("Secrets") && notSuccess;
        const has80211Word = error.includes("802.11") && notSuccess;

        return notSuccess && (hasSecretKeyword || hasPasswordWord || hasSecretsWord || has80211Word);
    }

    // --- Network parsing ---

    function parseNetworkOutput(output: string): list<var> {
        if (!output || output.length === 0) {
            return [];
        }

        const PLACEHOLDER = "STRINGWHICHHOPEFULLYWONTBEUSED";
        const rep = new RegExp("\\\\:", "g");
        const rep2 = new RegExp(PLACEHOLDER, "g");

        const allNetworks = output.trim().split("\n").filter(line => line && line.length > 0).map(n => {
            const net = n.replace(rep, PLACEHOLDER).split(":");
            return {
                active: net[0] === "yes",
                strength: parseInt(net[1] || "0", 10) || 0,
                frequency: parseInt(net[2] || "0", 10) || 0,
                ssid: (net[3]?.replace(rep2, ":") ?? "").trim(),
                bssid: (net[4]?.replace(rep2, ":") ?? "").trim(),
                security: (net[5] ?? "").trim()
            };
        }).filter(n => n.ssid && n.ssid.length > 0);

        return allNetworks;
    }

    function deduplicateNetworks(networks: list<var>): list<var> {
        if (!networks || networks.length === 0) {
            return [];
        }

        const networkMap = new Map();
        for (const network of networks) {
            const existing = networkMap.get(network.ssid);
            if (!existing) {
                networkMap.set(network.ssid, network);
            } else {
                if (network.active && !existing.active) {
                    networkMap.set(network.ssid, network);
                } else if (!network.active && !existing.active) {
                    if (network.strength > existing.strength) {
                        networkMap.set(network.ssid, network);
                    }
                }
            }
        }

        return Array.from(networkMap.values());
    }

    // --- Interface queries ---

    function getWirelessInterfaces(callback: var): void {
        NmcliCore.executeCommand(["-t", "-f", NmcliCore.deviceStatusFields, NmcliCore.nmcliCommandDevice, "status"], result => {
            const interfaces = NmcliCore.parseDeviceStatusOutput(result.output, NmcliCore.deviceTypeWifi);
            root.wirelessInterfaces = interfaces;
            if (callback)
                callback(interfaces);
        });
    }

    // --- WiFi radio ---

    function enableWifi(enabled: bool, callback: var): void {
        const cmd = enabled ? "on" : "off";
        NmcliCore.executeCommand([NmcliCore.nmcliCommandRadio, NmcliCore.nmcliCommandWifi, cmd], result => {
            if (result.success) {
                getWifiStatus(status => {
                    root.wifiEnabled = status;
                    if (callback)
                        callback(result);
                });
            } else {
                if (callback)
                    callback(result);
            }
        });
    }

    function toggleWifi(callback: var): void {
        const newState = !root.wifiEnabled;
        enableWifi(newState, callback);
    }

    function getWifiStatus(callback: var): void {
        NmcliCore.executeCommand([NmcliCore.nmcliCommandRadio, NmcliCore.nmcliCommandWifi], result => {
            if (result.success) {
                const enabled = result.output.trim() === "enabled";
                root.wifiEnabled = enabled;
                if (callback)
                    callback(enabled);
            } else {
                if (callback)
                    callback(root.wifiEnabled);
            }
        });
    }

    // --- Network scanning ---

    function rescanWifi(): void {
        rescanProc.running = true;
    }

    function scanWirelessNetworks(interfaceName: string, callback: var): void {
        let cmd = [NmcliCore.nmcliCommandDevice, NmcliCore.nmcliCommandWifi, "rescan"];
        if (interfaceName && interfaceName.length > 0) {
            cmd.push(NmcliCore.connectionParamIfname, interfaceName);
        }
        NmcliCore.executeCommand(cmd, result => {
            if (callback) {
                callback(result);
            }
        });
    }

    function getNetworks(callback: var): void {
        NmcliCore.executeCommand(["-g", NmcliCore.networkDetailFields, "d", "w"], result => {
            if (!result.success) {
                if (callback)
                    callback([]);
                return;
            }

            const allNetworks = parseNetworkOutput(result.output);
            const deduplicated = deduplicateNetworks(allNetworks);
            const rNetworks = root.networks;

            // Build a map of existing networks by composite key
            const existingMap = new Map();
            for (const rn of rNetworks) {
                const key = `${rn.frequency}:${rn.ssid}:${rn.bssid}`;
                existingMap.set(key, rn);
            }

            // Build updated list in one pass, reusing existing objects where possible
            const updated = [];
            const keptKeys = new Set();
            for (const network of deduplicated) {
                const key = `${network.frequency}:${network.ssid}:${network.bssid}`;
                const existing = existingMap.get(key);
                if (existing) {
                    existing.lastIpcObject = network;
                    updated.push(existing);
                } else {
                    updated.push(apComp.createObject(root, {
                        lastIpcObject: network
                    }));
                }
                keptKeys.add(key);
            }

            // Destroy removed networks after building the new list
            for (const [key, rn] of existingMap) {
                if (!keptKeys.has(key)) {
                    rn.destroy();
                }
            }

            // Single assignment — O(1) binding trigger
            root.networks = updated;

            if (callback)
                callback(root.networks);
            checkPendingConnection();
        });
    }

    function getWirelessSSIDs(interfaceName: string, callback: var): void {
        let cmd = ["-t", "-f", NmcliCore.networkListFields, NmcliCore.nmcliCommandDevice, NmcliCore.nmcliCommandWifi, "list"];
        if (interfaceName && interfaceName.length > 0) {
            cmd.push(NmcliCore.connectionParamIfname, interfaceName);
        }
        NmcliCore.executeCommand(cmd, result => {
            if (!result.success) {
                if (callback)
                    callback([]);
                return;
            }

            const ssids = [];
            const lines = result.output.trim().split("\n");
            const seenSSIDs = new Set();

            for (const line of lines) {
                if (!line || line.length === 0)
                    continue;

                const parts = line.split(":");
                if (parts.length >= 1) {
                    const ssid = parts[0].trim();
                    if (ssid && ssid.length > 0 && !seenSSIDs.has(ssid)) {
                        seenSSIDs.add(ssid);
                        const signalStr = parts.length >= 2 ? parts[1].trim() : "";
                        const signal = signalStr ? parseInt(signalStr, 10) : 0;
                        const security = parts.length >= 3 ? parts[2].trim() : "";
                        ssids.push({
                            ssid: ssid,
                            signal: signalStr,
                            signalValue: isNaN(signal) ? 0 : signal,
                            security: security
                        });
                    }
                }
            }

            ssids.sort((a, b) => {
                return b.signalValue - a.signalValue;
            });

            if (callback)
                callback(ssids);
        });
    }

    // --- Connection operations ---

    function connectToNetworkWithPasswordCheck(ssid: string, isSecure: bool, callback: var, bssid: string): void {
        if (isSecure) {
            connectWireless(ssid, "", bssid, result => {
                if (result.success) {
                    if (callback)
                        callback({
                            success: true,
                            usedSavedPassword: true,
                            output: result.output,
                            error: "",
                            exitCode: 0
                        });
                } else if (result.needsPassword) {
                    if (callback)
                        callback({
                            success: false,
                            needsPassword: true,
                            output: result.output,
                            error: result.error,
                            exitCode: result.exitCode
                        });
                } else {
                    if (callback)
                        callback(result);
                }
            });
        } else {
            connectWireless(ssid, "", bssid, callback);
        }
    }

    function connectToNetwork(ssid: string, password: string, bssid: string, callback: var): void {
        connectWireless(ssid, password, bssid, callback);
    }

    function connectWireless(ssid: string, password: string, bssid: string, callback: var, retryCount: int): void {
        const hasBssid = bssid !== undefined && bssid !== null && bssid.length > 0;
        const retries = retryCount !== undefined ? retryCount : 0;
        const maxRetries = 2;

        if (callback) {
            root.pendingConnection = {
                ssid: ssid,
                bssid: hasBssid ? bssid : "",
                callback: callback,
                retryCount: retries
            };
            connectionCheckTimer.start();
            immediateCheckTimer.checkCount = 0;
            immediateCheckTimer.start();
        }

        if (password && password.length > 0 && hasBssid) {
            const bssidUpper = bssid.toUpperCase();
            createConnectionWithPassword(ssid, bssidUpper, password, callback);
            return;
        }

        let cmd = [NmcliCore.nmcliCommandDevice, NmcliCore.nmcliCommandWifi, "connect", ssid];
        if (password && password.length > 0) {
            cmd.push(NmcliCore.connectionParamPassword, password);
        }
        NmcliCore.executeCommand(cmd, result => {
            if (result.needsPassword && callback) {
                callback(result);
                return;
            }

            if (!result.success && root.pendingConnection && retries < maxRetries) {
                console.warn("[NMCLI] Connection failed, retrying... (attempt " + (retries + 1) + "/" + maxRetries + ")");
                Qt.callLater(() => {
                    connectWireless(ssid, password, bssid, callback, retries + 1);
                }, 1000);
            } else if (!result.success && root.pendingConnection) {
                // Pending connection timers (connectionCheckTimer/immediateCheckTimer) handle
                // the failure — no explicit callback here, they will call it on timeout.
            } else if (result.success && callback) {
                // Success is also handled by the pending connection timers which detect
                // the active network change and call the callback with success: true.
            } else if (!result.success && !root.pendingConnection) {
                if (callback)
                    callback(result);
            }
        });
    }

    function createConnectionWithPassword(ssid: string, bssidUpper: string, password: string, callback: var): void {
        checkAndDeleteConnection(ssid, () => {
            const cmd = [NmcliCore.nmcliCommandConnection, "add", NmcliCore.connectionParamType, NmcliCore.deviceTypeWifi, NmcliCore.connectionParamConName, ssid, NmcliCore.connectionParamIfname, "*", NmcliCore.connectionParamSsid, ssid, NmcliCore.connectionParamBssid, bssidUpper, NmcliCore.securityKeyMgmt, NmcliCore.keyMgmtWpaPsk, NmcliCore.securityPsk, password];

            NmcliCore.executeCommand(cmd, result => {
                if (result.success) {
                    loadSavedConnections(() => {});
                    activateConnection(ssid, callback);
                } else {
                    const hasDuplicateWarning = result.error && (result.error.includes("another connection with the name") || result.error.includes("Reference the connection by its uuid"));

                    if (hasDuplicateWarning || (result.exitCode > 0 && result.exitCode < 10)) {
                        loadSavedConnections(() => {});
                        activateConnection(ssid, callback);
                    } else {
                        console.warn("[NMCLI] Connection profile creation failed, trying fallback...");
                        let fallbackCmd = [NmcliCore.nmcliCommandDevice, NmcliCore.nmcliCommandWifi, "connect", ssid, NmcliCore.connectionParamPassword, password];
                        NmcliCore.executeCommand(fallbackCmd, fallbackResult => {
                            if (callback)
                                callback(fallbackResult);
                        });
                    }
                }
            });
        });
    }

    function checkAndDeleteConnection(ssid: string, callback: var): void {
        NmcliCore.executeCommand([NmcliCore.nmcliCommandConnection, "show", ssid], result => {
            if (result.success) {
                NmcliCore.executeCommand([NmcliCore.nmcliCommandConnection, "delete", ssid], deleteResult => {
                    Qt.callLater(() => {
                        if (callback)
                            callback();
                    }, 300);
                });
            } else {
                if (callback)
                    callback();
            }
        });
    }

    function activateConnection(connectionName: string, callback: var): void {
        NmcliCore.executeCommand([NmcliCore.nmcliCommandConnection, "up", connectionName], result => {
            if (callback)
                callback(result);
        });
    }

    function disconnect(interfaceName: string, callback: var): void {
        if (interfaceName && interfaceName.length > 0) {
            NmcliCore.executeCommand([NmcliCore.nmcliCommandDevice, "disconnect", interfaceName], result => {
                if (callback)
                    callback(result.success ? result.output : "");
            });
        } else {
            NmcliCore.executeCommand([NmcliCore.nmcliCommandDevice, "disconnect", NmcliCore.deviceTypeWifi], result => {
                if (callback)
                    callback(result.success ? result.output : "");
            });
        }
    }

    function disconnectFromNetwork(): void {
        if (active && active.ssid) {
            NmcliCore.executeCommand([NmcliCore.nmcliCommandConnection, "down", active.ssid], result => {
                if (result.success) {
                    getNetworks(() => {});
                }
            });
        } else {
            NmcliCore.executeCommand([NmcliCore.nmcliCommandDevice, "disconnect", NmcliCore.deviceTypeWifi], result => {
                if (result.success) {
                    getNetworks(() => {});
                }
            });
        }
    }

    // --- Saved connections ---

    function loadSavedConnections(callback: var): void {
        NmcliCore.executeCommand(["-t", "-f", NmcliCore.connectionListFields, NmcliCore.nmcliCommandConnection, "show"], result => {
            if (!result.success) {
                root.savedConnections = [];
                root.savedConnectionSsids = [];
                if (callback)
                    callback([]);
                return;
            }

            parseConnectionList(result.output, callback);
        });
    }

    function parseConnectionList(output: string, callback: var): void {
        const lines = output.trim().split("\n").filter(line => line.length > 0);
        const wifiConnections = [];
        const connections = [];

        for (const line of lines) {
            const parts = line.split(":");
            if (parts.length >= 2) {
                const name = parts[0];
                const type = parts[1];
                connections.push(name);

                if (type === NmcliCore.connectionTypeWireless) {
                    wifiConnections.push(name);
                }
            }
        }

        root.savedConnections = connections;

        if (wifiConnections.length > 0) {
            root.wifiConnectionQueue = wifiConnections;
            root.currentSsidQueryIndex = 0;
            root.savedConnectionSsids = [];
            queryNextSsid(callback);
        } else {
            root.savedConnectionSsids = [];
            root.wifiConnectionQueue = [];
            if (callback)
                callback(root.savedConnectionSsids);
        }
    }

    function queryNextSsid(callback: var): void {
        if (root.currentSsidQueryIndex < root.wifiConnectionQueue.length) {
            const connectionName = root.wifiConnectionQueue[root.currentSsidQueryIndex];
            root.currentSsidQueryIndex++;

            NmcliCore.executeCommand(["-t", "-f", NmcliCore.wirelessSsidField, NmcliCore.nmcliCommandConnection, "show", connectionName], result => {
                if (result.success) {
                    processSsidOutput(result.output);
                }
                queryNextSsid(callback);
            });
        } else {
            root.wifiConnectionQueue = [];
            root.currentSsidQueryIndex = 0;
            if (callback)
                callback(root.savedConnectionSsids);
        }
    }

    function processSsidOutput(output: string): void {
        const lines = output.trim().split("\n");
        for (const line of lines) {
            if (line.startsWith("802-11-wireless.ssid:")) {
                const ssid = line.substring("802-11-wireless.ssid:".length).trim();
                if (ssid && ssid.length > 0) {
                    const ssidLower = ssid.toLowerCase();
                    const exists = root.savedConnectionSsids.some(s => s && s.toLowerCase() === ssidLower);
                    if (!exists) {
                        const newList = root.savedConnectionSsids.slice();
                        newList.push(ssid);
                        root.savedConnectionSsids = newList;
                    }
                }
            }
        }
    }

    function hasSavedProfile(ssid: string): bool {
        if (!ssid || ssid.length === 0) {
            return false;
        }
        const ssidLower = ssid.toLowerCase().trim();

        if (root.active && root.active.ssid) {
            const activeSsidLower = root.active.ssid.toLowerCase().trim();
            if (activeSsidLower === ssidLower) {
                return true;
            }
        }

        const hasSsid = root.savedConnectionSsids.some(savedSsid => savedSsid && savedSsid.toLowerCase().trim() === ssidLower);

        if (hasSsid) {
            return true;
        }

        const hasConnectionName = root.savedConnections.some(connName => connName && connName.toLowerCase().trim() === ssidLower);

        return hasConnectionName;
    }

    function forgetNetwork(ssid: string, callback: var): void {
        if (!ssid || ssid.length === 0) {
            if (callback)
                callback({
                    success: false,
                    output: "",
                    error: "No SSID specified",
                    exitCode: -1
                });
            return;
        }

        const connectionName = root.savedConnections.find(conn => conn && conn.toLowerCase().trim() === ssid.toLowerCase().trim()) || ssid;

        NmcliCore.executeCommand([NmcliCore.nmcliCommandConnection, "delete", connectionName], result => {
            if (result.success) {
                Qt.callLater(() => {
                    loadSavedConnections(() => {});
                }, 500);
            }
            if (callback)
                callback(result);
        });
    }

    // --- Device details ---

    function getWirelessDeviceDetails(interfaceName: string, callback: var): void {
        if (!interfaceName || interfaceName.length === 0) {
            const activeInterface = root.wirelessInterfaces.find(iface => {
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
                root.wirelessDeviceDetails = null;
                if (callback)
                    callback(null);
                return;
            }

            const details = NmcliCore.parseDeviceDetails(result.output, false);
            root.wirelessDeviceDetails = details;
            if (callback)
                callback(details);
        });
    }

    // --- Password required handling ---

    function handlePasswordRequired(proc: var, error: string, output: string, exitCode: int): bool {
        if (!proc || !error || error.length === 0) {
            return false;
        }

        if (!NmcliCore.isConnectionCommand(proc.command) || !root.pendingConnection || !root.pendingConnection.callback) {
            return false;
        }

        const needsPassword = detectPasswordRequired(error);

        if (needsPassword && !proc.callbackCalled && root.pendingConnection) {
            connectionCheckTimer.stop();
            immediateCheckTimer.stop();
            immediateCheckTimer.checkCount = 0;
            const pending = root.pendingConnection;
            root.pendingConnection = null;
            proc.callbackCalled = true;
            const result = {
                success: false,
                output: output || "",
                error: error,
                exitCode: exitCode,
                needsPassword: true
            };
            if (pending.callback) {
                pending.callback(result);
            }
            if (proc.callback && proc.callback !== pending.callback) {
                proc.callback(result);
            }
            return true;
        }

        return false;
    }

    // --- AccessPoint component ---

    component AccessPoint: QtObject {
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

    // --- Connection state timers ---

    Timer {
        id: connectionCheckTimer

        // 12s tolerates real-world wifi: DHCP, captive-portal redirect, 5GHz
        // association on bar/cafe APs. The previous 4s value declared timeout
        // before slow networks could finish associating, which then triggered
        // forgetNetwork(ssid) and destroyed the in-flight profile.
        interval: 12000
        onTriggered: {
            if (root.pendingConnection) {
                const connected = root.active && root.active.ssid === root.pendingConnection.ssid;

                if (!connected && root.pendingConnection.callback) {
                    let foundPasswordError = false;
                    for (let i = 0; i < NmcliCore.activeProcesses.length; i++) {
                        const proc = NmcliCore.activeProcesses[i];
                        if (proc && proc.stderr && proc.stderr.text) {
                            const error = proc.stderr.text.trim();
                            if (error && error.length > 0) {
                                if (NmcliCore.isConnectionCommand(proc.command)) {
                                    const needsPassword = root.detectPasswordRequired(error);

                                    if (needsPassword && !proc.callbackCalled && root.pendingConnection) {
                                        const pending = root.pendingConnection;
                                        root.pendingConnection = null;
                                        immediateCheckTimer.stop();
                                        immediateCheckTimer.checkCount = 0;
                                        proc.callbackCalled = true;
                                        const result = {
                                            success: false,
                                            output: (proc.stdout && proc.stdout.text) ? proc.stdout.text : "",
                                            error: error,
                                            exitCode: -1,
                                            needsPassword: true
                                        };
                                        if (pending.callback) {
                                            pending.callback(result);
                                        }
                                        if (proc.callback && proc.callback !== pending.callback) {
                                            proc.callback(result);
                                        }
                                        foundPasswordError = true;
                                        break;
                                    }
                                }
                            }
                        }
                    }

                    if (!foundPasswordError) {
                        const pending = root.pendingConnection;
                        const failedSsid = pending.ssid;
                        root.pendingConnection = null;
                        immediateCheckTimer.stop();
                        immediateCheckTimer.checkCount = 0;
                        root.connectionFailed(failedSsid);
                        pending.callback({
                            success: false,
                            output: "",
                            error: "Connection timeout",
                            exitCode: -1,
                            needsPassword: false
                        });
                    }
                } else if (connected) {
                    root.pendingConnection = null;
                    immediateCheckTimer.stop();
                    immediateCheckTimer.checkCount = 0;
                }
            }
        }
    }

    Timer {
        id: immediateCheckTimer

        property int checkCount: 0

        interval: 500
        repeat: true
        triggeredOnStart: false

        onTriggered: {
            if (root.pendingConnection) {
                checkCount++;
                const connected = root.active && root.active.ssid === root.pendingConnection.ssid;

                if (connected) {
                    connectionCheckTimer.stop();
                    immediateCheckTimer.stop();
                    immediateCheckTimer.checkCount = 0;
                    if (root.pendingConnection.callback) {
                        root.pendingConnection.callback({
                            success: true,
                            output: "Connected",
                            error: "",
                            exitCode: 0
                        });
                    }
                    root.pendingConnection = null;
                } else {
                    for (let i = 0; i < NmcliCore.activeProcesses.length; i++) {
                        const proc = NmcliCore.activeProcesses[i];
                        if (proc && proc.stderr && proc.stderr.text) {
                            const error = proc.stderr.text.trim();
                            if (error && error.length > 0) {
                                if (NmcliCore.isConnectionCommand(proc.command)) {
                                    const needsPassword = root.detectPasswordRequired(error);

                                    if (needsPassword && !proc.callbackCalled && root.pendingConnection && root.pendingConnection.callback) {
                                        connectionCheckTimer.stop();
                                        immediateCheckTimer.stop();
                                        immediateCheckTimer.checkCount = 0;
                                        const pending = root.pendingConnection;
                                        root.pendingConnection = null;
                                        proc.callbackCalled = true;
                                        const result = {
                                            success: false,
                                            output: (proc.stdout && proc.stdout.text) ? proc.stdout.text : "",
                                            error: error,
                                            exitCode: -1,
                                            needsPassword: true
                                        };
                                        if (pending.callback) {
                                            pending.callback(result);
                                        }
                                        if (proc.callback && proc.callback !== pending.callback) {
                                            proc.callback(result);
                                        }
                                        return;
                                    }
                                }
                            }
                        }
                    }

                    if (checkCount >= 6) {
                        immediateCheckTimer.stop();
                        immediateCheckTimer.checkCount = 0;
                    }
                }
            } else {
                immediateCheckTimer.stop();
                immediateCheckTimer.checkCount = 0;
            }
        }
    }

    function checkPendingConnection(): void {
        if (root.pendingConnection) {
            Qt.callLater(() => {
                const connected = root.active && root.active.ssid === root.pendingConnection.ssid;
                if (connected) {
                    connectionCheckTimer.stop();
                    immediateCheckTimer.stop();
                    immediateCheckTimer.checkCount = 0;
                    if (root.pendingConnection.callback) {
                        root.pendingConnection.callback({
                            success: true,
                            output: "Connected",
                            error: "",
                            exitCode: 0
                        });
                    }
                    root.pendingConnection = null;
                } else {
                    if (!immediateCheckTimer.running) {
                        immediateCheckTimer.start();
                    }
                }
            });
        }
    }

    // --- Rescan process ---

    Process {
        id: rescanProc

        command: ["nmcli", "dev", NmcliCore.nmcliCommandWifi, "list", "--rescan", "yes"]
        onExited: root.getNetworks()
    }

    // --- Initialization ---

    Component.onCompleted: {
        getWifiStatus(() => {});
        getNetworks(() => {});
        loadSavedConnections(() => {});

        Qt.callLater(() => {
            if (root.wirelessInterfaces.length > 0) {
                const activeWireless = root.wirelessInterfaces.find(iface => {
                    return NmcliCore.isConnectedState(iface.state);
                });
                if (activeWireless && activeWireless.device) {
                    getWirelessDeviceDetails(activeWireless.device, () => {});
                }
            }
        }, 2000);
    }
}
