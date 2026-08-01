pragma Singleton

import qs.services
import qs.config
import Quickshell
import Quickshell.Io
import QtQuick

/// State and logic for the Agent Overview feature.
///
/// A fullscreen layer-shell overlay (Super+A) that shows EVERY live agent the
/// shell knows about — IDE-hosted, standalone nvim, and remote — grouped by
/// Hyprland workspace, with an active/dormant filter. Unlike WindowOverview,
/// this is a LIVE monitor: it does not freeze a snapshot. Its content binds
/// reactively to AgentService.agents, so cards update in place as agents work.
///
/// IPC entry point: modules/agentoverview/Wrapper.qml routes
/// `symmetria shell agentoverview {show,hide,toggle,cycleFilter}` here. The
/// overlay UI lives in modules/agentoverview/OverviewSurface.qml and binds
/// reactively to this singleton's state.
Singleton {
    id: root

    /// Whether the overview is currently visible.
    property bool active: false

    /// Monitor frozen at show() time — the overlay renders only on this monitor.
    // intentional var: nullable HyprlandMonitor — null until show()
    property var targetMonitor: null

    /// Active filter: "all" (every alive agent) | "active" (busy) | "dormant" (idle).
    property string filterMode: "all"

    /// Cycle order for cycleFilter() / the Tab key.
    // intentional var: JS array of the three filter modes
    readonly property var _filterOrder: ["all", "active", "dormant"]

    /// Read-side conversation backfill: session_id -> {last_prompt, last_messages}.
    /// Populated by the reader Process below while the overlay is open, by reading
    /// each visible agent's Claude transcript directly (keyed by the session_id the
    /// bridge always knows). This is what fills the cards immediately — even for
    /// long-dormant agents the push-side never captured. Remote agents (transcript
    /// not on this machine) stay absent here and fall back to their pushed fields.
    // intentional var: JS object map keyed by session id
    property var conversations: ({})

    readonly property string _readerScript: Qt.resolvedUrl("../scripts/agent-overview-transcripts.py").toString().replace(/^file:\/\//, "")

    // ── Active vs dormant classification ─────────────────────────────
    // Active  = busy: thinking / working / needs_permission / starting / clearing.
    // Dormant = idle but ALIVE: "" or "idle" (offline agents are excluded entirely).

    function _stateOf(agent: var): string {
        return agent?.activity_state ?? "";
    }

    function isAgentActive(agent: var): bool {
        const s = root._stateOf(agent);
        return s !== "" && s !== "idle" && s !== "offline";
    }

    function isAgentDormant(agent: var): bool {
        const s = root._stateOf(agent);
        return s !== "offline" && !root.isAgentActive(agent);
    }

    function _agentAlive(agent: var): bool {
        return root._stateOf(agent) !== "offline";
    }

    function _matchesFilter(agent: var): bool {
        if (root.filterMode === "active")
            return root.isAgentActive(agent);
        if (root.filterMode === "dormant")
            return root.isAgentDormant(agent);
        return root._agentAlive(agent); // "all"
    }

    // ── Live, filtered workspace grouping ────────────────────────────
    // Mirrors MergedBarContent's reactivity pattern: agentsByWorkspace() is a
    // plain function, so calling it in a binding establishes NO dependency on
    // the underlying data. Pass AgentService.agents + _workspaceMap + filterMode
    // as arguments purely to trip the binding when any of them change; the
    // compute fn then re-derives and filters the grouping.
    // Gated on `active` so nothing recomputes while the overlay is closed. The
    // surface additionally gates its card model on per-monitor `shouldShow`, so
    // only the focused screen instantiates cards (and their live sparkles).
    readonly property var filteredGrouping: root.active ? root._computeFilteredGrouping(AgentService.agents, AgentService.workspaceMap, root.filterMode) : root._emptyGrouping

    // Stable empty grouping returned while the overlay is closed.
    readonly property var _emptyGrouping: ({
            byWorkspace: ({}),
            orphans: [],
            remote: []
        })

    function _computeFilteredGrouping(_agentsDep: var, _wsDep: var, _modeDep: string): var {
        const g = AgentService.agentsByWorkspace();
        const keep = arr => (arr ?? []).filter(a => root._matchesFilter(a));

        const byWs = {};
        for (const id in g.byWorkspace) {
            const kept = keep(g.byWorkspace[id]);
            if (kept.length > 0)
                byWs[id] = kept;
        }
        return {
            byWorkspace: byWs,
            orphans: keep(g.orphans),
            remote: keep(g.remote)
        };
    }

    // ── Counts for the filter control (over ALL alive agents) ────────

    // Gated on `active` (same reason as filteredGrouping) — the filter buttons
    // that read these counts only exist while the overlay is open.
    readonly property int activeCount: root.active ? root._countWhere(AgentService.agents, a => root.isAgentActive(a)) : 0
    readonly property int dormantCount: root.active ? root._countWhere(AgentService.agents, a => root.isAgentDormant(a)) : 0
    readonly property int aliveCount: root.activeCount + root.dormantCount

    function _countWhere(agents: var, pred: var): int {
        let n = 0;
        for (const a of (agents ?? [])) {
            if (pred(a))
                n++;
        }
        return n;
    }

    // ── Visibility ───────────────────────────────────────────────────

    function show(): void {
        if (active)
            return;
        if (!Config.agentOverview.enabled)
            return;

        const mon = Hypr.focusedMonitor;
        if (!mon) {
            console.warn("[AgentOverview] No focused monitor; refusing to show");
            return;
        }

        targetMonitor = mon;
        active = true;
        root._refreshConversations();
    }

    function hide(): void {
        if (!active)
            return;

        active = false;
        targetMonitor = null;
        conversations = ({});
    }

    function toggle(): void {
        if (active)
            hide();
        else
            show();
    }

    // ── Filter control ───────────────────────────────────────────────

    function setFilter(mode: string): void {
        if (root._filterOrder.includes(mode))
            filterMode = mode;
    }

    function cycleFilter(): void {
        const i = root._filterOrder.indexOf(filterMode);
        filterMode = root._filterOrder[(i + 1) % root._filterOrder.length];
    }

    function cycleFilterReverse(): void {
        const n = root._filterOrder.length;
        const i = root._filterOrder.indexOf(filterMode);
        filterMode = root._filterOrder[(i - 1 + n) % n];
    }

    // ── Click-to-focus ───────────────────────────────────────────────
    /// Focus an agent's host window, then dismiss the overlay.
    ///
    /// CRITICAL ordering: hide() FIRST, then Qt.callLater defers the focus
    /// dispatch one event-loop tick. A WlrKeyboardFocus.Exclusive layer makes
    /// wlroots atomically restore prior keyboard focus on unmap, which would
    /// clobber a synchronous focuswindow dispatch. Same pattern as
    /// WindowOverviewService.activateAddr — see docs/qml-pitfalls.md
    /// "Layer-shell focus restoration race".
    function focusAgentAndHide(agent: var): void {
        const pid = agent?.terminal_pid ?? 0;
        hide();
        if (pid > 0)
            Qt.callLater(() => AgentService.focusTerminal(pid));
    }

    /// Resolve an agent's conversation: prefer the read-side backfill (fresh,
    /// full transcript) keyed by session_id; fall back to the bridge-pushed
    /// fields (covers remote agents, whose transcript isn't readable locally).
    function conversationFor(agent: var): var {
        const sid = agent?.session_id ?? "";
        if (sid && root.conversations[sid])
            return root.conversations[sid];
        return {
            last_prompt: agent?.last_prompt ?? "",
            last_messages: agent?.last_messages ?? []
        };
    }

    /// Re-read transcripts for every visible agent that has a session_id. Runs on
    /// show() and every few seconds while open (so an active agent's text stays
    /// current); skipped when closed or when a prior read is still in flight.
    function _refreshConversations(): void {
        if (!root.active)
            return;
        if (convoReader.running)
            return;
        const sids = [];
        for (const a of AgentService.agents) {
            const sid = a.session_id ?? "";
            if (sid)
                sids.push(sid);
        }
        if (sids.length === 0) {
            root.conversations = ({});
            return;
        }
        convoReader.command = ["python3", root._readerScript].concat(sids);
        convoReader.running = true;
    }

    Process {
        id: convoReader

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.conversations = JSON.parse(text || "{}");
                } catch (e) {
                    // Keep the previous map on a parse failure rather than blanking.
                }
            }
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.active
        onTriggered: root._refreshConversations()
    }
}
