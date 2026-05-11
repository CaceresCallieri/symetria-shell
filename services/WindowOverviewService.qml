pragma Singleton

import qs.services
import qs.utils
import Quickshell
import Quickshell.Hyprland
import QtQuick

/// State and logic for the Window Overview feature.
///
/// The overview is a fullscreen layer-shell overlay on the focused monitor that
/// snapshots the active workspace's windows into a labeled grid. Pressing a
/// label key focuses that window and dismisses; Esc dismisses without focusing.
///
/// IPC entry point lives in modules/windowoverview/Wrapper.qml — that file
/// routes `symmetria shell overview {show,hide,toggle}` here. The overlay UI
/// lives in modules/windowoverview/OverviewSurface.qml and binds reactively to
/// this singleton's state.
Singleton {
    id: root

    /// Whether the overview is currently visible.
    property bool active: false

    /// Monitor frozen at show() time. Overlay only renders on this monitor —
    /// switching focus to a different monitor mid-overview triggers auto-hide.
    // intentional var: nullable HyprlandMonitor — null until show()
    property var targetMonitor: null

    /// Workspace id frozen at show() time. The auto-close watcher compares
    /// against Hypr.activeWsId and dismisses if they diverge.
    property int targetWorkspaceId: -1

    /// Tile slot model. Each entry: { isGroup, repClient, addr, label }.
    /// repClient is the HyprlandToplevel whose surface is captured.
    /// label is one of the 16 letters in labelSequence, or "" for unreachable
    /// overflow slots (17+ windows). Recomputed via _rebuildTiles().
    // intentional var: JS array of plain objects — Repeater consumes by index
    property var tiles: []

    /// Fast lookup from label letter (uppercase) to client address.
    /// Populated by _rebuildTiles(); consulted by activate().
    // intentional var: JS Map<string, string>
    property var labelMap: new Map()

    /// 16-slot label sequence: home row first (slots 1-8), top row second (9-16).
    /// Skips index-finger stretches (G/H, T/Y) and pinky reaches.
    /// Bottom row reserved for a future tier-3 extension to 24 slots.
    /// "Return" matches Qt.Key_Return / Qt.Key_Enter when normalized to text.
    readonly property var labelSequence: [
        "A", "S", "D", "F", "J", "K", "L", "Return",
        "Q", "W", "E", "R", "U", "I", "O", "P"
    ]

    /// Hyprland events that mutate window layout — drive reactive rebuilds while open.
    /// Mirrored from components/WorkspaceAppIcons.qml so the overview's reactivity
    /// matches the bar's exactly.
    // intentional var: JS Set for O(1) event-name lookup
    readonly property var _windowLayoutEvents: new Set([
        "openwindow", "closewindow",
        "movewindow", "movewindowv2",
        "togglegroup", "moveintogroup", "moveoutofgroup",
        "activewindowv2", "changegroupactive",
        "fullscreen"
    ])

    function show(): void {
        if (active)
            return;

        const mon = Hypr.focusedMonitor;
        const wsId = Hypr.focusedWorkspace?.id ?? -1;
        if (!mon || wsId === -1) {
            console.warn("[WindowOverview] No focused monitor or workspace; refusing to show");
            return;
        }

        targetMonitor = mon;
        targetWorkspaceId = wsId;
        _rebuildTiles();
        active = true;
    }

    function hide(): void {
        if (!active)
            return;

        active = false;
        targetMonitor = null;
        targetWorkspaceId = -1;
        tiles = [];
        labelMap = new Map();
    }

    function toggle(): void {
        if (active)
            hide();
        else
            show();
    }

    /// Resolve a label letter to an address and focus that window.
    /// Used by the overlay's key handler.
    function activate(letter: string): void {
        activateAddr(labelMap.get((letter ?? "").toUpperCase()) ?? "");
    }

    /// Focus a window by raw address. Used by tile click-to-focus, which works
    /// for overflow tiles past slot 16 that have no label.
    ///
    /// CRITICAL: hide() runs first, then Qt.callLater defers the dispatch one
    /// event-loop tick. This avoids a layer-shell focus-restoration race —
    /// wlroots atomically restores prior keyboard focus when our Exclusive
    /// layer unmaps, which clobbers any synchronous focuswindow dispatch.
    /// See docs/qml-pitfalls.md "Layer-shell focus restoration race".
    function activateAddr(addr: string): void {
        if (!active || !addr)
            return;

        hide();
        Qt.callLater(() => Hypr.dispatch(`focuswindow address:${addr}`));
    }

    /// Build the tile model from the canonical bar order.
    ///
    /// Calls AppIconsProcessor.processClients() — the SAME function the bar
    /// uses to order app icons — so labels match bar icon positions by
    /// construction. Tab groups collapse to one tile (clients[0] as
    /// representative; step 8 refines to active-tab resolution). Swallowed
    /// windows are excluded by AppIconsProcessor itself.
    ///
    /// First 16 entries get labels from labelSequence; 17+ render unlabeled
    /// (visible but unreachable from the keyboard in v1).
    function _rebuildTiles(): void {
        const newTiles = [];
        const newLabelMap = new Map();

        if (targetWorkspaceId === -1) {
            tiles = newTiles;
            labelMap = newLabelMap;
            return;
        }

        const model = AppIconsProcessor.processClients(targetWorkspaceId, Hypr.toplevels.values);
        const seq = labelSequence;

        for (let i = 0; i < model.length; i++) {
            const entry = model[i];
            const repClient = entry.clients[0];
            const addr = repClient?.lastIpcObject?.address ?? "";
            const label = i < seq.length ? seq[i] : "";

            newTiles.push({
                isGroup: entry.isGroup,
                repClient: repClient,
                addr: addr,
                label: label
            });

            if (label && addr)
                newLabelMap.set(label, addr);
        }

        tiles = newTiles;
        labelMap = newLabelMap;
    }

    /// Auto-close on workspace or monitor focus change.
    /// The overview is anchored to a single (monitor, workspace) pair captured
    /// at show() time; auto-refreshing labels mid-keypress would break muscle
    /// memory. Drift = dismiss.
    Connections {
        target: Hypr
        enabled: root.active

        function onActiveWsIdChanged(): void {
            if (Hypr.activeWsId !== root.targetWorkspaceId)
                root.hide();
        }

        function onFocusedMonitorChanged(): void {
            if (Hypr.focusedMonitor !== root.targetMonitor)
                root.hide();
        }
    }

    /// Reactive tile rebuild on window layout events while overview is open.
    /// Debounced 50ms to coalesce rapid event bursts (Hyprland emits multiple
    /// events for a single window operation). modelsEqual check inside
    /// _rebuildTiles short-circuits no-op rebuilds — see the cachedModel
    /// pattern in components/WorkspaceAppIcons.qml for the same approach.
    Timer {
        id: rebuildDebounce
        interval: 50
        onTriggered: root._rebuildTiles()
    }

    Connections {
        target: Hyprland
        enabled: root.active

        function onRawEvent(event: HyprlandEvent): void {
            if (root._windowLayoutEvents.has(event.name))
                rebuildDebounce.restart();
        }
    }
}
