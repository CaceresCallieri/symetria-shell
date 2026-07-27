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

    signal connectionFailed(string ssid)

    /// How long to let NetworkManager work before nmcli gives up. Association +
    /// WPA handshake + DHCP against a real access point routinely needs more than
    /// ten seconds; nmcli reports the real outcome the moment it settles, so a
    /// generous ceiling costs nothing and only bounds a genuinely stuck attempt.
    readonly property int connectTimeoutSeconds: 45

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
    //
    // DESIGN: nmcli's own exit code is the result. `nmcli --wait N device wifi
    // connect` (and `connection up`) block until NetworkManager has either
    // activated the connection or failed it, then report that outcome directly.
    // Every caller therefore learns the truth exactly once, when it is known.
    //
    // REGRESSION GUARD: do NOT reintroduce success/failure detection that polls
    // `root.active`. `active` is `networks.find(n => n.active)` — the FIRST
    // active access point across ALL wireless devices, which is not necessarily
    // the device a given connect ran on. The previous implementation inferred
    // the outcome that way across three overlapping timers (500ms × 6, then 12s)
    // and got it wrong in both directions: it declared timeouts on connections
    // NetworkManager had already activated, and its "connected" branch cleared
    // the pending state without ever invoking the callback, hanging the dialog
    // on "Connecting…" forever. Verified 2026-07-27 against a mac80211_hwsim
    // access point (scripts/wifi-testbed.sh): NM logged "Activation: successful,
    // device activated" at t+0.5s, and the 12s timeout path then deleted the
    // working profile at t+12s. See docs/wifi-connect-flow.md.

    /// Connect to a network, using its stored secret when one exists.
    /// Delivers { success, needsPassword, output, error, exitCode } to callback.
    /// needsPassword: true means the caller should prompt and then call
    /// connectToNetwork with the typed password.
    function connectToNetworkWithPasswordCheck(ssid: string, isSecure: bool, callback: var, bssid: string): void {
        if (!isSecure) {
            connectWireless(ssid, "", bssid, callback);
            return;
        }

        findProfileUuidsForSsid(ssid, uuids => {
            if (uuids.length === 0) {
                // No stored secret exists, so ask for one instead of probing.
                //
                // REGRESSION GUARD: do NOT "just try connecting" first to find
                // out. `nmcli device wifi connect <ssid>` without a password
                // creates a persistent, psk-less profile with autoconnect=yes
                // before it fails. NetworkManager then retried that dead profile
                // on its own for hours (observed 2026-07-27), and each failed
                // attempt left another one behind to poison the next.
                deliverConnectResult(ssid, callback, {
                    success: false,
                    output: "",
                    error: "No saved profile for this network",
                    exitCode: -1,
                    needsPassword: true
                });
                return;
            }

            if (uuids.length > 1) {
                // Duplicate same-named profiles are a known legacy artefact. We
                // activate the first, which may be the stale one — surface it so a
                // "wrong password" report on a network with a good saved profile is
                // diagnosable rather than mysterious.
                console.warn("[NMCLI] " + uuids.length + " saved profiles named '" + ssid + "'; activating " + uuids[0]);
            }

            NmcliCore.executeCommand(["--wait", String(root.connectTimeoutSeconds), NmcliCore.nmcliCommandConnection, "up", "uuid", uuids[0]], result => {
                deliverConnectResult(ssid, callback, result);
            });
        });
    }

    function connectToNetwork(ssid: string, password: string, bssid: string, callback: var): void {
        connectWireless(ssid, password, bssid, callback);
    }

    // bssid is accepted for call-site compatibility but deliberately unused:
    // profiles roam by SSID. Pinning 802-11-wireless.bssid makes them stop
    // matching after an AP reboot, on mesh networks, and when revisiting venues.
    function connectWireless(ssid: string, password: string, bssid: string, callback: var): void {
        if (password && password.length > 0) {
            connectWithSecret(ssid, password, callback);
            return;
        }

        NmcliCore.executeCommand(["--wait", String(root.connectTimeoutSeconds), NmcliCore.nmcliCommandDevice, NmcliCore.nmcliCommandWifi, "connect", ssid], result => {
            deliverConnectResult(ssid, callback, result);
        });
    }

    // Connect to a secured SSID with a freshly typed password. Removes every
    // stale profile sharing the SSID's name first — a leftover profile carrying a
    // wrong or absent psk otherwise wins over the new secret — then runs the
    // atomic connect so the psk travels in the same command that activates.
    //
    // REGRESSION GUARD: do NOT split this into `connection add` + `connection up`.
    // That sequence (removed 2026-07-15) fell back to activating the OLD psk-less
    // profile on a duplicate-name warning, and NetworkManager failed instantly
    // with no-secrets because Symmetria registers no NM secret agent.
    function connectWithSecret(ssid: string, password: string, callback: var): void {
        deleteProfilesForSsid(ssid, () => {
            const cmd = [
                "--wait", String(root.connectTimeoutSeconds),
                NmcliCore.nmcliCommandDevice, NmcliCore.nmcliCommandWifi, "connect", ssid,
                NmcliCore.connectionParamPassword, password
            ];
            NmcliCore.executeCommand(cmd, result => {
                if (!result.success && result.needsPassword) {
                    // The password was rejected, so the profile this very command
                    // just created carries a known-bad psk AND autoconnect=yes —
                    // NetworkManager would keep retrying it on its own. Remove it
                    // before reporting the failure.
                    //
                    // This is NOT the indiscriminate forgetNetwork-on-failure that
                    // used to destroy working connections. The difference is what
                    // authorises the delete: that code deleted on a timeout it
                    // INFERRED by polling, and was wrong whenever the connection had
                    // actually succeeded. This deletes only when nmcli itself
                    // returned non-zero with a secrets error, which means
                    // NetworkManager definitively did not connect. Keep that
                    // distinction if you ever revisit this.
                    deleteProfilesForSsid(ssid, () => {
                        deliverConnectResult(ssid, callback, result);
                    });
                    return;
                }
                deliverConnectResult(ssid, callback, result);
            });
        });
    }

    // Single exit point for every connect path: refresh derived state, announce
    // a genuine failure, and hand the caller the one authoritative result.
    //
    // Note what this deliberately does NOT do: delete the profile on failure.
    // Automatic forgetNetwork() on the failure path used to destroy profiles that
    // had in fact connected successfully. Stale profiles are cleaned up at the
    // start of the NEXT attempt (connectWithSecret), where doing so is safe
    // because nothing is in flight.
    function deliverConnectResult(ssid: string, callback: var, result: var): void {
        if (result.success) {
            // Refresh the network list and saved-profile cache so the UI reflects
            // the new active network. `nmcli monitor` also triggers this, but not
            // deterministically enough for a callback consumer to rely on.
            getNetworks(() => {});
            loadSavedConnections(() => {});
        } else if (!result.needsPassword) {
            // Only a genuine failure. "No stored secret, ask the user" is a normal
            // step of a first-time connect, not something consumers should surface
            // as an error.
            root.connectionFailed(ssid);
        }

        if (callback) {
            callback({
                success: result.success === true,
                needsPassword: result.needsPassword === true,
                output: result.output || "",
                error: result.error || "",
                exitCode: result.exitCode
            });
        }
    }

    // Live lookup of every saved profile whose NAME equals the SSID, addressed by
    // UUID. Duplicate same-named profiles exist in the wild (a legacy of the old
    // racy connect path), and deleting by name is ambiguous once they do.
    function findProfileUuidsForSsid(ssid: string, callback: var): void {
        NmcliCore.executeCommand(["-t", "-f", "UUID,NAME", NmcliCore.nmcliCommandConnection, "show"], result => {
            const uuids = [];
            if (result.success && result.output) {
                const target = ssid.trim().toLowerCase();
                const lines = result.output.trim().split("\n");
                for (const line of lines) {
                    // -t terse output escapes ':' inside values as '\:'. The UUID
                    // field never contains ':', so the first ':' splits UUID | NAME.
                    const idx = line.indexOf(":");
                    if (idx < 0)
                        continue;
                    const uuid = line.substring(0, idx);
                    const name = line.substring(idx + 1).replace(/\\:/g, ":");
                    if (name.trim().toLowerCase() === target)
                        uuids.push(uuid);
                }
            }
            if (callback)
                callback(uuids);
        });
    }

    // Remove every saved profile named after this SSID, then continue. Pairs the
    // live UUID lookup with the sequential delete — the two are never useful apart.
    function deleteProfilesForSsid(ssid: string, callback: var): void {
        findProfileUuidsForSsid(ssid, uuids => {
            deleteUuidsSequentially(uuids, 0, callback);
        });
    }

    function deleteUuidsSequentially(uuids: var, index: int, callback: var): void {
        if (index >= uuids.length) {
            if (callback)
                callback();
            return;
        }
        NmcliCore.executeCommand([NmcliCore.nmcliCommandConnection, "delete", "uuid", uuids[index]], result => {
            if (!result.success)
                console.warn("[NMCLI] Failed to delete profile uuid " + uuids[index] + ": " + (result.error || ""));
            deleteUuidsSequentially(uuids, index + 1, callback);
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

    /// Disconnect a specific network. Callers know which network the user acted
    /// on and must say so; omitting the SSID falls back to whatever `active`
    /// resolves to, which is only unambiguous with a single wireless radio.
    ///
    /// REGRESSION GUARD: do NOT go back to deriving the target from `active`
    /// alone. `active` is `networks.find(n => n.active)` — the first active AP
    /// across ALL wireless devices. On 2026-07-27, with two radios connected,
    /// asking to disconnect one network took down the OTHER one.
    function disconnectFromNetwork(ssid: string): void {
        if (!ssid || ssid.length === 0) {
            // Refuse rather than guess. Falling back to `active` here is exactly the
            // hazard the guard above describes, and every caller already knows which
            // network the user acted on.
            console.warn("[NMCLI] disconnectFromNetwork called with no SSID — ignoring");
            return;
        }

        NmcliCore.executeCommand([NmcliCore.nmcliCommandConnection, "down", ssid], result => {
            if (result.success) {
                getNetworks(() => {});
            }
        });
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
                // No delay needed — `connection delete` has already returned, so
                // the profile is gone by the time we re-read the list. (This used
                // to read `Qt.callLater(fn, 500)`, which does NOT delay: trailing
                // arguments are passed TO fn. The intended wait never happened.)
                loadSavedConnections(() => {});
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

        // A real Timer, because the wait is real intent: the interface list is
        // populated asynchronously above and device details are useless before it
        // lands. REGRESSION GUARD: do NOT collapse this back to
        // `Qt.callLater(fn, 2000)` — Qt.callLater cannot delay; its trailing
        // arguments are passed TO fn, so that form ran immediately against an
        // empty wirelessInterfaces list and silently fetched nothing.
        deviceDetailsBootstrapTimer.start();
    }

    Timer {
        id: deviceDetailsBootstrapTimer

        interval: 2000
        onTriggered: {
            if (root.wirelessInterfaces.length === 0)
                return;
            const activeWireless = root.wirelessInterfaces.find(iface => NmcliCore.isConnectedState(iface.state));
            if (activeWireless && activeWireless.device)
                root.getWirelessDeviceDetails(activeWireless.device, () => {});
        }
    }
}
