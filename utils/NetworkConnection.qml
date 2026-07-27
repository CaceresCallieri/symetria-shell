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
     * Connect to a network. Does NOT disconnect the active connection first —
     * see the regression guard below.
     *
     * @param network The network object to connect to (must have ssid property)
     * @param session Optional Session object (for controlcenter - must have network property with showPasswordDialog and pendingNetwork)
     * @param onPasswordNeeded Optional callback function(network) called when password is needed (for bar popouts)
     * @param onResult Optional callback function(result) invoked on every terminal
     *        outcome — success, failure, or needsPassword. Callers that show a
     *        pending state (row spinners, buttons) MUST pass this; it is the only
     *        signal that the attempt finished.
     */
    function handleConnect(network: var, session: var, onPasswordNeeded: var, onResult: var): void {
        if (!network) {
            console.warn("[NetworkConnection] handleConnect called with no network");
            if (onResult)
                onResult(root.noNetworkResult());
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
        root.connectToNetwork(network, session, onPasswordNeeded, onResult);
    }

    // Shared terminal result for the "caller gave us nothing to connect to"
    // guards. Every early return MUST deliver one of these: a guard that returns
    // silently leaves the caller's pending UI (button disabled, row spinning)
    // with nothing that can ever clear it — the exact permanent-"Connecting…"
    // failure this whole flow was rewritten to eliminate.
    function noNetworkResult(): var {
        return {
            success: false,
            needsPassword: false,
            output: "",
            error: "No network specified",
            exitCode: -1
        };
    }

    /**
     * Connect to a wireless network.
     * Handles both secured and open networks, checks for saved profiles,
     * and shows password dialog if needed.
     * 
     * @param network The network object to connect to (must have ssid, isSecure, bssid properties)
     * @param session Optional Session object (for controlcenter - must have network property with showPasswordDialog and pendingNetwork)
     * @param onPasswordNeeded Optional callback function(network) called when password is needed (for bar popouts)
     * @param onResult Optional callback function(result) invoked on every terminal outcome
     */
    function connectToNetwork(network: var, session: var, onPasswordNeeded: var, onResult: var): void {
        if (!network) {
            console.warn("[NetworkConnection] connectToNetwork called with no network");
            if (onResult)
                onResult(root.noNetworkResult());
            return;
        }

        if (!network.isSecure) {
            NmcliWifi.connectToNetwork(network.ssid, "", network.bssid, onResult || null);
            return;
        }

        // Secured network: connectToNetworkWithPasswordCheck activates the saved
        // profile when one exists, and returns needsPassword immediately when none
        // does — it does NOT probe with an empty password first. See
        // docs/wifi-connect-flow.md ("No empty-password probe").
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
                    // REGRESSION GUARD: reach into another component only through
                    // declared properties. The removed code called Timer ids inside
                    // the NmcliWifi singleton; QML ids are file-scoped, so they were
                    // always undefined here.

                    // Handle password dialog - use session if available, otherwise use callback
                    if (session && session.network) {
                        session.network.showPasswordDialog = true;
                        session.network.pendingNetwork = network;
                    } else if (onPasswordNeeded) {
                        onPasswordNeeded(network);
                    }
                }
                if (onResult)
                    onResult(result);
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
            console.warn("[NetworkConnection] connectWithPassword called with no network");
            if (onResult)
                onResult(root.noNetworkResult());
            return;
        }

        NmcliWifi.connectToNetwork(network.ssid, password || "", network.bssid || "", onResult || null);
    }
}

