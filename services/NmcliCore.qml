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
    readonly property string securityKeyMgmt: "802-11-wireless-security.key-mgmt"
    readonly property string securityPsk: "802-11-wireless-security.psk"
    readonly property string keyMgmtWpaPsk: "wpa-psk"
    readonly property string connectionParamType: "type"
    readonly property string connectionParamConName: "con-name"
    readonly property string connectionParamIfname: "ifname"
    readonly property string connectionParamSsid: "ssid"
    readonly property string connectionParamPassword: "password"
    readonly property string connectionParamBssid: "802-11-wireless.bssid"

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
            proc.exec(proc.command);
        });
    }

    function isConnectionCommand(command: list<string>): bool {
        if (!command || command.length === 0) {
            return false;
        }

        return command.includes(root.nmcliCommandWifi) || command.includes(root.nmcliCommandConnection);
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

    // --- CommandProcess component ---
    // NOTE: Intentional layer inversion — CommandProcess references NmcliWifi
    // for password detection (handlePasswordRequired, detectPasswordRequired,
    // pendingConnection, connectionFailed). This coupling exists because password
    // errors arrive via stderr on ANY nmcli process, and the detection must happen
    // at the process level before the generic callback fires. Refactoring to a
    // signal-based approach risks breaking the delicate password detection flow.

    component CommandProcess: Process {
        id: proc

        // intentional var: nullable JS function reference (callback from executeCommand callers)
        property var callback: null
        property list<string> command: []
        property bool callbackCalled: false
        property int exitCode: 0

        signal processFinished

        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })

        stdout: StdioCollector {
            id: stdoutCollector
        }

        stderr: StdioCollector {
            id: stderrCollector

            onStreamFinished: {
                const error = text.trim();
                if (error && error.length > 0) {
                    const output = (stdoutCollector && stdoutCollector.text) ? stdoutCollector.text : "";
                    NmcliWifi.handlePasswordRequired(proc, error, output, -1);
                }
            }
        }

        onExited: code => {
            exitCode = code;

            Qt.callLater(() => {
                if (callbackCalled) {
                    processFinished();
                    return;
                }

                if (proc.callback) {
                    const output = (stdoutCollector && stdoutCollector.text) ? stdoutCollector.text : "";
                    const error = (stderrCollector && stderrCollector.text) ? stderrCollector.text : "";
                    const success = exitCode === 0;
                    const cmdIsConnection = root.isConnectionCommand(proc.command);

                    if (NmcliWifi.handlePasswordRequired(proc, error, output, exitCode)) {
                        processFinished();
                        return;
                    }

                    const needsPassword = cmdIsConnection && NmcliWifi.detectPasswordRequired(error);

                    if (!success && cmdIsConnection && NmcliWifi.pendingConnection) {
                        const failedSsid = NmcliWifi.pendingConnection.ssid;
                        NmcliWifi.connectionFailed(failedSsid);
                    }

                    callbackCalled = true;
                    callback({
                        success: success,
                        output: output,
                        error: error,
                        exitCode: proc.exitCode,
                        needsPassword: needsPassword || false
                    });
                    processFinished();
                } else {
                    processFinished();
                }
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
                Qt.callLater(() => {
                    if (NmcliWifi.wirelessInterfaces.length > 0) {
                        const activeWireless = NmcliWifi.wirelessInterfaces.find(iface => {
                            return isConnectedState(iface.state);
                        });
                        if (activeWireless && activeWireless.device) {
                            NmcliWifi.getWirelessDeviceDetails(activeWireless.device, () => {});
                        }
                    }

                    if (NmcliEthernet.ethernetInterfaces.length > 0) {
                        const activeEth = NmcliEthernet.ethernetInterfaces.find(iface => {
                            return isConnectedState(iface.state);
                        });
                        if (activeEth && activeEth.device) {
                            NmcliEthernet.getEthernetDeviceDetails(activeEth.device, () => {});
                        }
                    }
                }, 500);
            } else {
                NmcliWifi.wirelessDeviceDetails = null;
                NmcliEthernet.ethernetDeviceDetails = null;
            }

            NmcliWifi.getWirelessInterfaces(() => {});
            NmcliEthernet.getEthernetInterfaces(() => {
                if (NmcliEthernet.activeEthernet && NmcliEthernet.activeEthernet.connected) {
                    Qt.callLater(() => {
                        NmcliEthernet.getEthernetDeviceDetails(NmcliEthernet.activeEthernet.interface, () => {});
                    }, 500);
                }
            });
        });
    }

    Component.onCompleted: {
        refreshStatus(() => {});
    }
}
