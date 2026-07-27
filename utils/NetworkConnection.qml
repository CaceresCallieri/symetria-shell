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
    function handleConnect(network: var, session: var, onPasswordNeeded: var): void {
        if (!network) {
            return;
        }

        // REGRESSION GUARD: do NOT disconnect the currently active network first.
        // NetworkManager already deactivates the old connection as part of
        // activating the new one on the same device, so the explicit teardown
        // bought nothing and cost plenty: it left the machine with no network at
        // all if the new connection then failed, and — because every saved
        // profile has autoconnect=yes — NetworkManager immediately raced to
        // auto-activate some unrelated saved network in the gap. Observed
        // 2026-07-27: tapping one network dropped the live connection and sent NM
        // chasing a completely different SSID. It was also sequenced with
        // Qt.callLater, which does not wait for the disconnect to finish.
        root.connectToNetwork(network, session, onPasswordNeeded);
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
    function connectToNetwork(network: var, session: var, onPasswordNeeded: var): void {
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
                    // Nothing to tear down here: NmcliWifi settles its own in-flight
                    // state before invoking this callback.
                    //
                    // REGRESSION GUARD: this block used to poke
                    // NmcliWifi.connectionCheckTimer / .immediateCheckTimer. Those
                    // were `Timer { id: ... }` declarations INSIDE the singleton,
                    // not exposed properties — QML ids are file-scoped, so from
                    // here they were `undefined` and the calls would have thrown.
                    // Reach into another component only through declared properties.

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
    function connectWithPassword(network: var, password: string, onResult: var): void {
        if (!network) {
            return;
        }

        NmcliWifi.connectToNetwork(network.ssid, password || "", network.bssid || "", onResult || null);
    }
}

