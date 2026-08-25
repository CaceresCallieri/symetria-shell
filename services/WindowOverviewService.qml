pragma Singleton

import qs.services
import qs.utils
import Quickshell
import Quickshell.Hyprland
import QtQuick

/// State and transitions for the Dwindle window navigator.
///
/// The navigator labels the real windows in the focused workspace. When it is
/// invoked from maximized or fullscreen state, it temporarily returns the
/// focused window to the layout, then transfers the captured fullscreen state
/// to the selected window. Cancelling restores the original window and state.
Singleton {
    id: root

    /// True when window labels are ready for selection.
    property bool active: false

    /// True while Hyprland exposes and settles the Dwindle tree.
    property bool revealing: false

    readonly property bool sessionActive: active || revealing

    /// Stable monitor and workspace identity captured before layout mutation.
    property string targetMonitorName: ""
    property int targetWorkspaceId: -1

    /// Original focus and fullscreen state. `fullscreen` is Hyprland's internal
    /// state; `fullscreenClient` is the state communicated to the application.
    property string sourceAddress: ""
    property int sourceFullscreen: 0
    property int sourceFullscreenClient: 0

    /// One entry per visible Dwindle slot: { repClient, addr, label }.
    property var tiles: []

    /// Fast lookup from an uppercase label to a client address.
    property var labelMap: new Map()

    /// Invalidates deferred focus/state callbacks when a new action starts.
    property int _actionToken: 0
    property int _revealRetries: 0
    property int _focusRestoreToken: 0
    property int _focusRestoreRetries: 0
    property string _focusRestoreAddress: ""
    property int _focusRestoreInternal: 0
    property int _focusRestoreClient: 0

    /// Home row first, then top row. Return occupies the easy right-pinky slot.
    readonly property var labelSequence: ["A", "S", "D", "F", "J", "K", "L", "Return", "Q", "W", "E", "R", "U", "I", "O", "P"]

    /// Topology changes invalidate frozen label assignments. A fullscreen event
    /// is handled separately because it is the expected reveal transition.
    readonly property var _topologyEvents: new Set(["openwindow", "closewindow", "movewindow", "movewindowv2", "togglegroup", "moveintogroup", "moveoutofgroup", "activewindowv2", "changegroupactive", "changefloatingmode", "minimize"])

    function show(): void {
        if (sessionActive)
            return;

        const monitor = Hypr.focusedMonitor;
        const workspace = Hypr.focusedWorkspace;
        // Use the raw Hyprland singleton. Hypr.activeToplevel intentionally has
        // a Wayland activation guard that can be null during a valid IPC state.
        const source = Hyprland.activeToplevel;
        const ipc = source?.lastIpcObject;
        const address = ipc?.address ?? "";

        if (!monitor || !workspace || !address) {
            console.warn("[WindowOverview] No focused window, monitor, or workspace; refusing to show");
            return;
        }

        _clearPendingFocusRestore();
        const revealToken = ++_actionToken;
        targetMonitorName = monitor.name;
        targetWorkspaceId = workspace.id;
        sourceAddress = address;
        sourceFullscreen = ipc.fullscreen ?? 0;
        sourceFullscreenClient = ipc.fullscreenClient ?? sourceFullscreen;
        _revealRetries = 0;
        revealing = true;

        if (_hasFullscreenState(sourceFullscreen, sourceFullscreenClient)) {
            // Clear both halves explicitly. The selected window receives the
            // exact captured pair after focus changes, while Escape restores it
            // to this source window.
            Hypr.dispatch("fullscreenstate 0 0 set");
            // The fullscreen event normally arrives first and restarts this
            // timer. This run is the fallback if the event is lost.
            revealSettleTimer.restart();
        } else {
            // Normal mode does not mutate geometry. Defer one tick so the
            // keyboard layer maps before labels can accept input.
            Qt.callLater(() => {
                if (revealToken === root._actionToken)
                    root._finishReveal();
            });
        }
    }

    function hide(): void {
        cancel();
    }

    function toggle(): void {
        if (sessionActive)
            cancel();
        else
            show();
    }

    function activate(letter: string): void {
        activateAddr(labelMap.get((letter ?? "").toUpperCase()) ?? "");
    }

    /// Select an address and transfer the invocation fullscreen state to it.
    function activateAddr(address: string): void {
        if (!active || !address)
            return;

        if (!_addressExists(address)) {
            cancel();
            return;
        }

        _finish(address, sourceFullscreen, sourceFullscreenClient);
    }

    /// Restore the exact focus and fullscreen pair captured at show() time.
    function cancel(): void {
        if (!sessionActive)
            return;

        const address = sourceAddress;
        const fullscreen = sourceFullscreen;
        const fullscreenClient = sourceFullscreenClient;

        if (!address || !_addressExists(address)) {
            _actionToken++;
            _resetSession();
            return;
        }

        _finish(address, fullscreen, fullscreenClient);
    }

    /// Unmap before changing focus. Fullscreen state waits for Hyprland to
    /// confirm the target focus because dispatch() uses asynchronous socket IPC.
    function _finish(address: string, fullscreen: int, fullscreenClient: int): void {
        const token = ++_actionToken;
        _resetSession();

        Qt.callLater(() => {
            if (token !== root._actionToken || !root._addressExists(address))
                return;

            Hypr.dispatch(`focuswindow address:${address}`);

            if (root._hasFullscreenState(fullscreen, fullscreenClient)) {
                root._focusRestoreToken = token;
                root._focusRestoreAddress = address;
                root._focusRestoreInternal = fullscreen;
                root._focusRestoreClient = fullscreenClient;
                root._focusRestoreRetries = 0;
                focusRestoreTimer.start();
            }
        });
    }

    function _finishReveal(): void {
        if (!revealing)
            return;

        const monitorName = Hypr.focusedMonitor?.name ?? "";
        const workspaceId = Hypr.focusedWorkspace?.id ?? -1;
        if (monitorName !== targetMonitorName || workspaceId !== targetWorkspaceId) {
            cancel();
            return;
        }

        const source = _clientForAddress(sourceAddress);
        const currentInternal = source?.lastIpcObject?.fullscreen ?? 0;
        const currentClient = source?.lastIpcObject?.fullscreenClient ?? 0;
        if (_hasFullscreenState(sourceFullscreen, sourceFullscreenClient) && _hasFullscreenState(currentInternal, currentClient)) {
            if (_revealRetries < 3) {
                _revealRetries++;
                Hyprland.refreshToplevels();
                revealRefreshTimer.restart();
                return;
            }

            console.warn("[WindowOverview] Dwindle reveal did not clear fullscreen; restoring source state");
            cancel();
            return;
        }

        _rebuildTiles();
        if (tiles.length === 0) {
            cancel();
            return;
        }

        active = true;
        revealing = false;
    }

    /// Build labels after Dwindle exposes the real window geometry. Labels stay
    /// frozen for the session, while each delegate reads live client geometry.
    function _rebuildTiles(): void {
        const processed = AppIconsProcessor.processClients(targetWorkspaceId, Hypr.toplevels.values);
        const nextTiles = [];
        const nextLabelMap = new Map();

        for (let index = 0; index < processed.length; index++) {
            const entry = processed[index];
            const representative = _representativeClient(entry.clients);
            const address = representative?.lastIpcObject?.address ?? "";
            if (!address)
                continue;

            const labelIndex = nextTiles.length;
            const label = labelIndex < labelSequence.length ? labelSequence[labelIndex] : "";
            nextTiles.push({
                repClient: representative,
                addr: address,
                label: label
            });

            if (label)
                nextLabelMap.set(label, address);
        }

        tiles = nextTiles;
        labelMap = nextLabelMap;
    }

    /// A Hyprland group occupies one real rectangle. The most recently focused
    /// non-hidden member is the best available proxy for its visible tab.
    function _representativeClient(clients: var): var {
        if (!clients || clients.length === 0)
            return null;

        const candidates = clients.filter(client => !client.lastIpcObject?.hidden);
        if (candidates.length === 0)
            return null;

        return [...candidates].sort((left, right) => {
            const leftHistory = left.lastIpcObject?.focusHistoryID ?? Number.MAX_SAFE_INTEGER;
            const rightHistory = right.lastIpcObject?.focusHistoryID ?? Number.MAX_SAFE_INTEGER;
            return leftHistory - rightHistory;
        })[0];
    }

    function _addressExists(address: string): bool {
        return _clientForAddress(address) !== null;
    }

    function _clientForAddress(address: string): var {
        return Hypr.toplevels.values.find(client => client.lastIpcObject?.address === address) ?? null;
    }

    function _hasFullscreenState(internal: int, client: int): bool {
        return internal !== 0 || client !== 0;
    }

    function _clearPendingFocusRestore(): void {
        focusRestoreTimer.stop();
        _focusRestoreToken = 0;
        _focusRestoreRetries = 0;
        _focusRestoreAddress = "";
        _focusRestoreInternal = 0;
        _focusRestoreClient = 0;
    }

    function _resetSession(): void {
        active = false;
        revealing = false;
        revealSettleTimer.stop();
        revealRefreshTimer.stop();
        _clearPendingFocusRestore();
        targetMonitorName = "";
        targetWorkspaceId = -1;
        sourceAddress = "";
        sourceFullscreen = 0;
        sourceFullscreenClient = 0;
        _revealRetries = 0;
        tiles = [];
        labelMap = new Map();
    }

    /// Coalesce the fullscreen event and Dwindle geometry updates. Refresh the
    /// IPC model before reading the final window rectangles.
    Timer {
        id: revealSettleTimer
        interval: 120
        repeat: false
        onTriggered: {
            Hyprland.refreshToplevels();
            revealRefreshTimer.restart();
        }
    }

    Timer {
        id: revealRefreshTimer
        interval: 40
        repeat: false
        onTriggered: root._finishReveal()
    }

    /// `focuswindow` and `fullscreenstate` both target compositor state through
    /// asynchronous IPC. Poll the authoritative active toplevel for at most
    /// 500ms so fullscreenstate never lands on the previously focused client.
    Timer {
        id: focusRestoreTimer
        interval: 20
        repeat: true

        onTriggered: {
            const address = root._focusRestoreAddress;
            if (root._focusRestoreToken !== root._actionToken || !root._addressExists(address)) {
                root._clearPendingFocusRestore();
                return;
            }

            const activeAddress = Hyprland.activeToplevel?.lastIpcObject?.address ?? "";
            if (activeAddress === address) {
                const internal = root._focusRestoreInternal;
                const client = root._focusRestoreClient;
                root._clearPendingFocusRestore();
                Hypr.dispatch(`fullscreenstate ${internal} ${client} set`);
                return;
            }

            root._focusRestoreRetries++;
            if (root._focusRestoreRetries >= 25) {
                console.warn(`[WindowOverview] Focus did not reach ${address}; fullscreen state was not restored`);
                root._clearPendingFocusRestore();
            }
        }
    }

    Connections {
        target: Hypr
        enabled: root.sessionActive

        function onActiveWsIdChanged(): void {
            if (Hypr.activeWsId !== root.targetWorkspaceId)
                root.cancel();
        }

        function onFocusedMonitorChanged(): void {
            if ((Hypr.focusedMonitor?.name ?? "") !== root.targetMonitorName)
                root.cancel();
        }
    }

    Connections {
        target: Hyprland
        enabled: root.sessionActive

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "fullscreen") {
                if (root.revealing)
                    revealSettleTimer.restart();
                else
                    root.cancel();
                return;
            }

            if (event.name === "closewindow") {
                const eventAddress = event.data ?? "";
                const closedAddress = eventAddress.startsWith("0x") ? eventAddress : `0x${eventAddress}`;
                if (closedAddress === root.sourceAddress) {
                    root._actionToken++;
                    root._resetSession();
                    return;
                }
            }

            if (root._topologyEvents.has(event.name))
                root.cancel();
        }
    }
}
