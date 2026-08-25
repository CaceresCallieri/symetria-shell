pragma ComponentBehavior: Bound

import qs.services
import qs.utils
import Quickshell
import Quickshell.Hyprland
import QtQuick

/// Headless provider of the position-sorted app-icon model for one workspace.
/// Owns the AppIconsProcessor call, the event-driven debounced refresh, and the
/// modelsEqual churn-gate — the single source of truth for "which windows, grouped
/// and sorted, are on this workspace". Consumed by both the top-bar WorkspaceAppIcons
/// and the agentbar MergedWindowAgentRow so this plumbing exists in exactly one place.
///
/// Non-visual (QtObject): it must never participate in a Row/Layout — it only computes
/// `model`. Callers bind a Repeater to `windowModel.model`.
QtObject {
    id: root

    required property int workspaceId

    /// Array<{ isGroup: bool, clients: HyprlandToplevel[] }> — position-sorted.
    /// intentional var: heterogeneous JS objects from AppIconsProcessor
    property var model: []

    // Events that affect window positions, lifecycle, grouping, or fullscreen state (Set for O(1) lookup).
    // activewindowv2 included because Hyprland 0.54+ doesn't emit togglegroup events;
    // focus changes are the closest proxy. modelsEqual() prevents unnecessary rerenders.
    // fullscreen included to trigger re-sort when entering/exiting fullscreen — ensures
    // the tiled order cache in AppIconsProcessor is populated and position sort resumes promptly.
    // intentional var: JS Set for O(1) event name lookup (no QML Set type)
    readonly property var _windowLayoutEvents: new Set(["openwindow", "closewindow", "movewindow", "movewindowv2", "togglegroup", "moveintogroup", "moveoutofgroup", "activewindowv2", "changegroupactive", "fullscreen"])

    function update(): void {
        const result = AppIconsProcessor.processClients(root.workspaceId, Hypr.toplevels.values);
        if (!AppIconsProcessor.modelsEqual(result, root.model))
            root.model = result;
    }

    // Use the debounce for all initialization paths to prevent race conditions.
    Component.onCompleted: _debounce.restart()
    onWorkspaceIdChanged: _debounce.restart()

    // Debounce timer - coalesces rapid Hyprland events into a single update.
    // 50ms chosen empirically: fast enough for responsive UI, slow enough to batch
    // rapid event bursts (e.g., togglegroup emits multiple events in quick succession).
    property Timer _debounce: Timer {
        interval: 50
        onTriggered: root.update()
    }

    // Listen to Hyprland events - only update on relevant events.
    property Connections _events: Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (root._windowLayoutEvents.has(event.name))
                root._debounce.restart();
        }
    }
}
