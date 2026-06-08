pragma Singleton

import qs.services
import QtQuick

/**
 * NetworkConnection
 * 
 * Centralized utility for network connection logic. Provides a single source of truth
 * for connecting to wireless networks, eliminating code duplication across
 * controlcenter components and bar popouts.
 * 
 * Usage:
 * ```qml
 * import qs.utils
 * 
 * // With Session object (controlcenter)
 * NetworkConnection.handleConnect(network, session);
 * 
 * // Without Session object (bar popouts) - provide password dialog callback
 * NetworkConnection.handleConnect(network, null, (network) => {
 *     // Show password dialog
 *     root.passwordNetwork = network;
 *     root.showPasswordDialog = true;
 * });
 * ```
 */
QtObject {
    id: root

    /**
     * Handle network connection with automatic disconnection if needed.
     * If there's an active network different from the target, disconnects first,
     * then connects to the target network.
     * 
     * @param network The network object to connect to (must have ssid property)
     * @param session Optional Session object (for controlcenter - must have network property with showPasswordDialog and pendingNetwork)
     * @param onPasswordNeeded Optional callback function(network) called when password is needed (for bar popouts)
     */
    function handleConnect(network, session, onPasswordNeeded): void {
        if (!network) {
            return;
        }

        if (NmcliWifi.active && NmcliWifi.active.ssid !== network.ssid) {
            NmcliWifi.disconnectFromNetwork();
            Qt.callLater(() => {
                root.connectToNetwork(network, session, onPasswordNeeded);
            });
        } else {
            root.connectToNetwork(network, session, onPasswordNeeded);
        }
    }

    /**
     * Connect to a wireless network.
     * Handles both secured and open networks, checks for saved profiles,
     * and shows password dialog if needed.
     * 
     * @param network The network object to connect to (must have ssid, isSecure, bssid properties)
     * @param session Optional Session object (for controlcenter - must have network property with showPasswordDialog and pendingNetwork)
     * @param onPasswordNeeded Optional callback function(network) called when password is needed (for bar popouts)
     */
    function connectToNetwork(network, session, onPasswordNeeded): void {
        if (!network) {
            return;
        }

        if (!network.isSecure) {
            NmcliWifi.connectToNetwork(network.ssid, "", network.bssid, null);
            return;
        }

        // Secured network: attempt with the stored secret first (an empty password
        // reuses any saved profile's PSK), and prompt ONLY if nmcli reports the
        // secret is missing/rejected. This single path covers three cases: no saved
        // profile, a saved profile with a good secret (connects silently), and a
        // saved profile whose secret is stale/wrong (re-prompts).
        //
        // REGRESSION GUARD: do NOT reintroduce a `hasSavedProfile()` fast path that
        // calls connectToNetwork(..., null). Symmetria registers no NetworkManager
        // secret agent, so when a saved profile's secret is bad, NM fails instantly
        // with "no-secrets / No agents available". With a null callback that failure
        // was SILENT — the user clicked Connect and nothing happened, the root cause
        // of "I can only connect to networks I've connected to before". The callback
        // below is the only thing that surfaces the password dialog on that failure.
        NmcliWifi.connectToNetworkWithPasswordCheck(
            network.ssid,
            network.isSecure,
            (result) => {
                if (result.needsPassword) {
                    // Clear pending connection if exists
                    if (NmcliWifi.pendingConnection) {
                        NmcliWifi.connectionCheckTimer.stop();
                        NmcliWifi.immediateCheckTimer.stop();
                        NmcliWifi.immediateCheckTimer.checkCount = 0;
                        NmcliWifi.pendingConnection = null;
                    }

                    // Handle password dialog - use session if available, otherwise use callback
                    if (session && session.network) {
                        session.network.showPasswordDialog = true;
                        session.network.pendingNetwork = network;
                    } else if (onPasswordNeeded) {
                        onPasswordNeeded(network);
                    }
                }
            },
            network.bssid
        );
    }

    /**
     * Connect to a wireless network with a provided password.
     * Used by password dialogs when the user has already entered a password.
     * 
     * @param network The network object to connect to (must have ssid, bssid properties)
     * @param password The password to use for connection
     * @param onResult Optional callback function(result) called with connection result
     */
    function connectWithPassword(network, password, onResult): void {
        if (!network) {
            return;
        }

        NmcliWifi.connectToNetwork(network.ssid, password || "", network.bssid || "", onResult || null);
    }
}

