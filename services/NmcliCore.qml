pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.services

/// Shared nmcli infrastructure: constants, command execution, process management,
/// parsing utilities, device status, and the network monitor.
///
/// NmcliWifi and NmcliEthernet delegate command execution to this singleton.
Singleton {
    id: root

    // --- Shared state ---

    // intentional var: JS array with in-place mutations (.push(), .splice(), .indexOf())
    //   — mutations are silent (no change signal); this is an internal registry, not a reactive model
    property var activeProcesses: []

    // --- Constants ---
    readonly property string deviceTypeWifi: "wifi"
    readonly property string deviceTypeEthernet: "ethernet"
    readonly property string deviceTypeAll: "both"
    readonly property string connectionTypeWireless: "802-11-wireless"
    readonly property string nmcliCommandDevice: "device"
    readonly property string nmcliCommandConnection: "connection"
    readonly property string nmcliCommandWifi: "wifi"
    readonly property string nmcliCommandRadio: "radio"
    readonly property string deviceStatusFields: "DEVICE,TYPE,STATE,CONNECTION"
    readonly property string connectionListFields: "NAME,TYPE"
    readonly property string wirelessSsidField: "802-11-wireless.ssid"
    readonly property string networkListFields: "SSID,SIGNAL,SECURITY"
    readonly property string networkDetailFields: "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY"
    readonly property string connectionParamIfname: "ifname"
    readonly property string connectionParamPassword: "password"

    // --- Command execution ---

    function executeCommand(args: list<string>, callback: var): void {
        const proc = commandProc.createObject(root);
        proc.command = ["nmcli", ...args];
        proc.callback = callback;

        activeProcesses.push(proc);

        proc.processFinished.connect(() => {
            const index = activeProcesses.indexOf(proc);
            if (index >= 0) {
                activeProcesses.splice(index, 1);
            }
        });

        Qt.callLater(() => {
            proc.startWatchdog();
            proc.exec(proc.command);
        });
    }

    function isConnectionCommand(command: list<string>): bool {
        if (!command || command.length === 0) {
            return false;
        }

        // Only commands that actually ACTIVATE a connection can meaningfully
        // report "secrets required". Read-only queries (`connection show`,
        // `device wifi list`) must not have their stderr mined for password
        // keywords — that produced needsPassword on commands that never tried
        // to connect.
        return command.includes("connect") || (command.includes(root.nmcliCommandConnection) && command.includes("up"));
    }

    // --- Parsing utilities ---

    function parseDeviceStatusOutput(output: string, filterType: string): list<var> {
        if (!output || output.length === 0) {
            return [];
        }

        const interfaces = [];
        const lines = output.trim().split("\n");

        for (const line of lines) {
            const parts = line.split(":");
            if (parts.length >= 2) {
                const deviceType = parts[1];
                let shouldInclude = false;

                if (filterType === root.deviceTypeWifi && deviceType === root.deviceTypeWifi) {
                    shouldInclude = true;
                } else if (filterType === root.deviceTypeEthernet && deviceType === root.deviceTypeEthernet) {
                    shouldInclude = true;
                }

                if (shouldInclude) {
                    interfaces.push({
                        device: parts[0] || "",
                        type: parts[1] || "",
                        state: parts[2] || "",
                        connection: parts[3] || ""
                    });
                }
            }
        }

        return interfaces;
    }

    function isConnectedState(state: string): bool {
        if (!state || state.length === 0) {
            return false;
        }

        return state === "100 (connected)" || state === "connected" || state.startsWith("connected");
    }

    function parseDeviceDetails(output: string, isEthernet: bool): var {
        const details = {
            ipAddress: "",
            gateway: "",
            dns: [],
            subnet: "",
            macAddress: "",
            speed: ""
        };

        if (!output || output.length === 0) {
            return details;
        }

        const lines = output.trim().split("\n");

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const parts = line.split(":");
            if (parts.length >= 2) {
                const key = parts[0].trim();
                const value = parts.slice(1).join(":").trim();

                if (key.startsWith("IP4.ADDRESS")) {
                    const ipParts = value.split("/");
                    details.ipAddress = ipParts[0] || "";
                    if (ipParts[1]) {
                        details.subnet = cidrToSubnetMask(ipParts[1]);
                    } else {
                        details.subnet = "";
                    }
                } else if (key === "IP4.GATEWAY") {
                    if (value !== "--") {
                        details.gateway = value;
                    }
                } else if (key.startsWith("IP4.DNS")) {
                    if (value !== "--" && value.length > 0) {
                        details.dns.push(value);
                    }
                } else if (isEthernet && key === "WIRED-PROPERTIES.MAC") {
                    details.macAddress = value;
                } else if (isEthernet && key === "WIRED-PROPERTIES.SPEED") {
                    details.speed = value;
                } else if (!isEthernet && key === "GENERAL.HWADDR") {
                    details.macAddress = value;
                }
            }
        }

        return details;
    }

    function cidrToSubnetMask(cidr: string): string {
        const cidrNum = parseInt(cidr, 10);
        if (isNaN(cidrNum) || cidrNum < 0 || cidrNum > 32) {
            return "";
        }

        const mask = (0xffffffff << (32 - cidrNum)) >>> 0;
        const octet1 = (mask >>> 24) & 0xff;
        const octet2 = (mask >>> 16) & 0xff;
        const octet3 = (mask >>> 8) & 0xff;
        const octet4 = mask & 0xff;

        return `${octet1}.${octet2}.${octet3}.${octet4}`;
    }

    // --- Device status queries ---

    function refreshStatus(callback: var): void {
        executeCommand(["-t", "-f", root.deviceStatusFields, root.nmcliCommandDevice, "status"], result => {
            const lines = result.output.trim().split("\n");
            let connected = false;
            let activeIf = "";
            let activeConn = "";

            for (const line of lines) {
                const parts = line.split(":");
                if (parts.length >= 4) {
                    const state = parts[2] || "";
                    if (isConnectedState(state)) {
                        connected = true;
                        activeIf = parts[0] || "";
                        activeConn = parts[3] || "";
                        break;
                    }
                }
            }

            if (callback)
                callback({
                    connected,
                    interface: activeIf,
                    connection: activeConn
                });
        });
    }

    // --- Password detection ---
    // A pure predicate over nmcli's stderr. It lives here, in the nmcli layer,
    // because it describes nmcli's own output vocabulary — no wifi-domain state
    // is involved. (It previously lived in NmcliWifi, which forced CommandProcess
    // into a documented layer inversion; that inversion is gone.)

    function detectPasswordRequired(error: string): bool {
        if (!error || error.length === 0) {
            return false;
        }

        const notSuccess = !error.includes("Connection activated") && !error.includes("successfully");
        const hasSecretKeyword = error.includes("Secrets were required")
            || error.includes("No secrets provided")
            || error.includes("802-11-wireless-security.psk")
            || error.includes("password for")
            || error.includes("No agents were available");
        const hasPasswordWord = error.includes("password") && notSuccess;
        const hasSecretsWord = error.includes("Secrets") && notSuccess;
        const has80211Word = error.includes("802.11") && notSuccess;

        return notSuccess && (hasSecretKeyword || hasPasswordWord || hasSecretsWord || has80211Word);
    }

    // --- CommandProcess component ---

    component CommandProcess: Process {
        id: proc

        // intentional var: nullable JS function reference (callback from executeCommand callers)
        property var callback: null
        property list<string> command: []
        property bool callbackCalled: false
        property int exitCode: 0

        signal processFinished

        // Guarantees the callback contract even when the process never exits.
        // Everything upstream assumes "the callback always fires exactly once";
        // without this, a nmcli that fails to spawn or wedges reproduces the exact
        // permanent-"Connecting…" hang this whole flow was rewritten to eliminate.
        // The ceiling sits above NmcliWifi.connectTimeoutSeconds (45s) so nmcli's
        // own --wait reports the real outcome first in every normal case.
        function deliver(success: bool, output: string, error: string, code: int): void {
            if (callbackCalled)
                return;
            callbackCalled = true;
            watchdog.stop();
            if (proc.callback) {
                proc.callback({
                    success: success,
                    output: output,
                    error: error,
                    exitCode: code,
                    needsPassword: root.isConnectionCommand(proc.command) && root.detectPasswordRequired(error)
                });
            }
        }

        function startWatchdog(): void {
            watchdog.start();
        }

        Timer {
            id: watchdog

            interval: 60000
            onTriggered: {
                console.warn("[NMCLI] no response after 60s, abandoning: " + proc.command.join(" "));
                proc.deliver(false, "", "nmcli did not respond", -1);
                proc.running = false;
                proc.processFinished();
            }
        }

        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })

        stdout: StdioCollector {
            id: stdoutCollector
        }

        stderr: StdioCollector {
            id: stderrCollector
        }

        // The process exit IS the result. nmcli blocks until NetworkManager has
        // settled the operation, so there is nothing left to infer afterwards:
        // exit code 0 means it worked, and stderr says why when it did not.
        onExited: code => {
            exitCode = code;

            Qt.callLater(() => {
                proc.deliver(code === 0,
                    (stdoutCollector && stdoutCollector.text) ? stdoutCollector.text : "",
                    (stderrCollector && stderrCollector.text) ? stderrCollector.text : "",
                    code);
                processFinished();
            });
        }
    }

    Component {
        id: commandProc

        CommandProcess {}
    }

    // --- Network monitor ---
    // Watches for connection changes and refreshes wifi + ethernet state.

    Process {
        id: monitorProc

        running: true
        command: ["nmcli", "monitor"]
        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })
        stdout: SplitParser {
            onRead: root.refreshOnConnectionChange()
        }
        onExited: monitorRestartTimer.start()
    }

    Timer {
        id: monitorRestartTimer
        interval: 2000
        onTriggered: {
            monitorProc.running = true;
        }
    }

    function refreshOnConnectionChange(): void {
        NmcliWifi.getNetworks(networks => {
            const newActive = NmcliWifi.active;

            if (newActive && newActive.active) {
                // A real Timer, because the wait is real intent: NetworkManager
                // needs a moment after activation before IP/DNS details are
                // populated. REGRESSION GUARD: do NOT collapse this back to
                // `Qt.callLater(fn, 500)` — Qt.callLater cannot delay; its trailing
                // arguments are passed TO fn, so that form ran immediately and read
                // details NetworkManager had not filled in yet.
                deviceDetailsRefreshTimer.restart();
            } else {
                NmcliWifi.wirelessDeviceDetails = null;
                NmcliEthernet.ethernetDeviceDetails = null;
            }

            NmcliWifi.getWirelessInterfaces(() => {});
            NmcliEthernet.getEthernetInterfaces(() => {
                if (NmcliEthernet.activeEthernet && NmcliEthernet.activeEthernet.connected) {
                    deviceDetailsRefreshTimer.restart();
                }
            });
        });
    }

    // Settle window after a NetworkManager state change, before re-reading the
    // IP/DNS details of whatever is now active. restart() coalesces the burst of
    // monitor events a single connect produces into one refresh.
    Timer {
        id: deviceDetailsRefreshTimer

        interval: 500
        onTriggered: {
            const activeWireless = NmcliWifi.wirelessInterfaces.find(iface => root.isConnectedState(iface.state));
            if (activeWireless && activeWireless.device)
                NmcliWifi.getWirelessDeviceDetails(activeWireless.device, () => {});

            const activeEth = NmcliEthernet.ethernetInterfaces.find(iface => root.isConnectedState(iface.state));
            if (activeEth && activeEth.device)
                NmcliEthernet.getEthernetDeviceDetails(activeEth.device, () => {});
        }
    }

    Component.onCompleted: {
        refreshStatus(() => {});
    }
}
