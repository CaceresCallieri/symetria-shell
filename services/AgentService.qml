pragma Singleton

import qs.config
import qs.services
import qs.utils
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import Symmetria

/// AgentService — bridges orchestrator.nvim agent state into QML.
///
/// Spawns agent-bridge.py (a Unix socket server) and reads its stdout
/// for consolidated JSON lines describing all active Claude Code agents
/// across all connected Neovim instances.
///
/// Usage:
///   AgentService.agents    → array of agent objects
///   AgentService.projects  → sorted unique project names
///   AgentService.agentCount → total active agents
Singleton {
    id: root

    // Public read-only state
    // intentional var: agents are heterogeneous JS objects from bridge JSON
    readonly property var agents: _agents
    // intentional var: JS array — used with .filter()/.sort()/.find() in _sortProjectsByWorkspace
    readonly property var projects: _projects
    readonly property int agentCount: _agents.length

    // Private mutable backing for userHidden
    property bool _userHidden: false

    /// Session-only visibility toggle (not persisted to shell.json).
    /// When true, the agent bar is hidden regardless of agent count.
    /// Mutated only via IpcHandler functions toggle/show/hide.
    readonly property bool userHidden: _userHidden

    /// Whether the merged workspace+agent bar mode is active.
    /// True when the config flag is on AND agents are visible.
    readonly property bool mergeActive: Config.agentbar.mergeWorkspaces
        && Config.agentbar.enabled
        && _agents.length > 0
        && !_userHidden

    /// Projects sorted by workspace: named (left) → normal 1-10 (middle) → special (right).
    /// Depends on _projects, _agents, _workspaceMap so it re-sorts when any change.
    // intentional var: JS array from [...projects].sort() — spread + sort requires JS array semantics
    readonly property var sortedProjects: _sortProjectsByWorkspace(_projects, _agents, _workspaceMap)

    /// Whether the bridge process is alive (does NOT mean the socket is ready —
    /// there is a ~50-100ms startup window before the asyncio server binds).
    readonly property bool bridgeRunning: bridgeProcess.running

    // ── STT target tracking ────────────────────────────────────────────
    // Set by SttService at recording start; cleared on idle/cancel.
    // AgentChip reads these to show a sound wave badge on the targeted agent.
    readonly property int sttTargetTerminalPid: _sttTargetTerminalPid
    readonly property int sttTargetBufId: _sttTargetBufId  // -1 = representative agent

    // True while the active STT job is in any post-recording phase
    // (processing / transcribed / delivering), per the SttJob state machine
    // (SttJob.qml:18). AgentChip uses this to swap the looping center-pulse
    // sprite for the left-to-right traveling wave during the transcribing window.
    // "success" and "error" are intentionally excluded — the chip stops showing
    // the STT animation before the job reaches those terminal states (clearSttTarget
    // fires on success/error, which sets isSttTarget = false → _sttWaving = false).
    // NOTE: This creates a circular singleton read: AgentService → SttService,
    // while SttJob (owned by SttService) already calls back into AgentService
    // (setSttTarget / clearSttTarget). QML resolves all qs.services singletons
    // before any binding evaluates, so the circular read is safe at runtime —
    // but be aware of this coupling when refactoring either service.
    readonly property bool sttIsTranscribing: {
        const j = SttService.job;
        if (!j) return false;
        const s = j.state;
        return s === "processing" || s === "transcribed" || s === "delivering";
    }

    // Internal state — always reassigned (never mutated in-place) so QML
    // bindings on agents/agentCount fire correctly. Do not use .push()/.splice().
    // intentional var: heterogeneous JS objects from bridge JSON
    property var _agents: []
    // intentional var: JS array — used with .filter()/.sort()/.find() downstream
    property var _projects: []
    property int _restartCount: 0
    readonly property int _maxRestartDelay: 30000

    // State-update throttling: leading edge fires immediately, then 100ms cooldown.
    // During cooldown, only the latest update is buffered (intermediate states are
    // skipped since the next emission always contains the full consolidated state).
    // intentional var: nullable JSON object from bridge stdout — no concrete QML type
    property var _pendingUpdate: null
    property bool _throttleActive: false

    // Resolve script path relative to this QML file
    // Qt.resolvedUrl returns "file:///abs/path" on Linux; strip "file://" to get "/abs/path"
    readonly property string _bridgeScript: Qt.resolvedUrl("../scripts/agent-bridge.py").toString().replace(/^file:\/\//, "")

    // M3 palette for agent dot colors (8 colors matching orchestrator's palette)
    readonly property list<color> palette: [
        Colours.palette.m3primary,
        Colours.palette.m3secondary,
        Colours.palette.m3tertiary,
        Colours.palette.m3error,
        Colours.palette.m3primaryContainer,
        Colours.palette.m3secondaryContainer,
        Colours.palette.m3tertiaryContainer,
        Colours.palette.m3errorContainer,
    ]

    function colorForIndex(idx: int): color {
        return palette[idx % palette.length];
    }

    // ── Workspace detection ──────────────────────────────────────────
    // Maps terminal_pid → {id, name} by scanning Hypr.toplevels.
    // Rebuilt on Hyprland window events and when _agents changes.

    property int _sttTargetTerminalPid: -1
    property int _sttTargetBufId: -1

    /// terminal_pid → {id: int, name: string}
    // intentional var: JS object used as hash map (pid → workspace info)
    property var _workspaceMap: ({})

    on_AgentsChanged: wsRebuildDebounce.restart()

    function _rebuildWorkspaceMap(): void {
        const pids = new Set();
        for (const agent of root._agents) {
            if (agent.terminal_pid)
                pids.add(agent.terminal_pid);
        }
        if (pids.size === 0) {
            root._workspaceMap = {};
            return;
        }

        const newMap = {};
        for (const toplevel of Hypr.toplevels.values) {
            const ipc = toplevel.lastIpcObject;
            if (ipc && pids.has(ipc.pid)) {
                const ws = ipc.workspace;
                if (ws)
                    newMap[ipc.pid] = { id: ws.id, name: ws.name };
            }
        }
        root._workspaceMap = newMap;
    }

    /// Get workspace {id, name} for a single agent, or null.
    function workspaceForAgent(agent: var): var {
        if (!agent || !agent.terminal_pid) return null;
        return root._workspaceMap[agent.terminal_pid] ?? null;
    }

    /// Focus the terminal window hosting a given agent (switches workspace if needed).
    /// No-ops silently if the window is not found in Hypr.toplevels (e.g., within
    /// the ~100ms debounce window after a window open event).
    function focusTerminal(terminalPid: int): void {
        if (terminalPid <= 0) return;
        for (const toplevel of Hypr.toplevels.values) {
            const ipc = toplevel.lastIpcObject;
            if (ipc && ipc.pid === terminalPid) {
                Hypr.dispatch(`focuswindow address:${ipc.address}`);
                return;
            }
        }
    }

    /// Returns the active agent in a group, or the first agent if none is active.
    function representativeAgent(agents: var): var {
        if (!agents || agents.length === 0) return null;
        return agents.find(a => a.active) ?? agents[0];
    }

    /// Pick representative workspace for a group of agents:
    /// active agent's workspace, or first agent's workspace.
    function workspaceForAgents(agents: var): var {
        return root.workspaceForAgent(root.representativeAgent(agents));
    }

    /// Group agents by workspace ID for the merged bar.
    /// Returns { byWorkspace: { [wsId]: agent[] }, orphans: agent[], remote: agent[] }
    /// Remote agents (tunneled via SSH) are separated from orphans for distinct display.
    /// Depends on _agents and _workspaceMap so callers get reactive updates.
    function agentsByWorkspace(): var {
        const byWs = {};
        const orphans = [];
        const remote = [];
        for (const agent of root._agents) {
            if (agent.remote) {
                remote.push(agent);
            } else {
                const ws = root._workspaceMap[agent.terminal_pid];
                if (ws) {
                    const id = ws.id;
                    if (!byWs[id]) byWs[id] = [];
                    byWs[id].push(agent);
                } else {
                    orphans.push(agent);
                }
            }
        }
        return { byWorkspace: byWs, orphans, remote };
    }

    /// Resolve workspace to display icon, matching the workspace bar's chain:
    /// special ws → getSpecialWsIcon, named ws → getNamedWsIcon, numbered → romanize
    function workspaceIconForWsId(wsId: int): string {
        // Look up workspace object from Hyprland for name-based resolution
        const ws = Hypr.workspaceById(wsId);

        if (ws) {
            // Special workspaces (negative ID, name starts with "special:")
            if (wsId < 0 && ws.name.startsWith("special:"))
                return Icons.getSpecialWsIcon(ws.name);
            // Named workspaces — try config icon, fall back to first letter
            const namedIcon = Icons.getNamedWsIcon(ws.name);
            if (namedIcon && namedIcon !== Icons.materialIconPrefix)
                return namedIcon;
            if (wsId < 0 && ws.name)
                return ws.name[0].toUpperCase();
        }
        // Regular numbered workspace → Roman numeral
        return Icons.romanize(wsId);
    }

    // ── Project sorting by workspace ─────────────────────────────────

    /// Workspace sort category:
    ///   0 = persistent named workspace (negative ID, no "special:" prefix) → leftmost
    ///   1 = normal workspace (ID >= 1) → middle
    ///   2 = special workspace (negative ID, "special:" prefix) → rightmost
    ///   3 = no workspace detected → far right
    function _wsSortKey(wsInfo: var): var {
        if (!wsInfo) return { category: 3, order: 0 };

        const id = wsInfo.id;
        const name = wsInfo.name ?? "";

        if (id < 0 && name.startsWith("special:"))
            return { category: 2, order: id };
        if (id < 0)
            return { category: 0, order: id };
        return { category: 1, order: id };
    }

    // wsMap: intentionally unused in the body — included so QML tracks _workspaceMap
    // as a dependency of the sortedProjects binding and re-sorts on workspace changes.
    function _sortProjectsByWorkspace(projects: var, agents: var, wsMap: var): var {
        // Precompute per-project workspace keys once, O(A) total
        const projectKey = {};
        for (const project of projects) {
            const projectAgents = agents.filter(ag => ag.project === project);
            projectKey[project] = root._wsSortKey(root.workspaceForAgents(projectAgents));
        }

        return [...projects].sort((a, b) => {
            const keyA = projectKey[a];
            const keyB = projectKey[b];

            // Primary: by category
            if (keyA.category !== keyB.category)
                return keyA.category - keyB.category;

            // Within any category: ascending by workspace ID
            // (named: most-negative first; normal: 1→10; special: by ID)
            if (keyA.order !== keyB.order)
                return keyA.order - keyB.order;

            // Fallback: alphabetical by project name
            return a.localeCompare(b);
        });
    }

    // ── STT integration ────────────────────────────────────────────────

    /// Set the STT injection target. Called by SttService.start().
    function setSttTarget(terminalPid: int, bufId: int): void {
        _sttTargetTerminalPid = terminalPid;
        _sttTargetBufId = bufId;
        _pushSttState();
    }

    /// Clear the STT target highlight. Called by SttService on cancel/idle.
    function clearSttTarget(): void {
        _sttTargetTerminalPid = -1;
        _sttTargetBufId = -1;
        _pushSttState();
    }

    /// Mirror the STT target into the bridge hub (stdin pipe) so non-shell
    /// snapshot consumers — the Symmetria IDE's AgentTopBar — can render the
    /// same recording/transcribing soundwave this dashboard computes locally
    /// via isAgentSttTarget(). The shell owns bridgeProcess, so its stdin is
    /// a zero-reconnect control channel; if the hub is down the write is a
    /// silent no-op and the next setSttTarget after restart resyncs.
    function _pushSttState(): void {
        if (!bridgeProcess.running) return;
        bridgeProcess.write(JSON.stringify({
            type: "stt_state",
            terminal_pid: _sttTargetTerminalPid,
            buf: _sttTargetBufId,
            transcribing: sttIsTranscribing
        }) + "\n");
    }

    // The recording→transcribing flip happens without a setSttTarget call
    // (sttIsTranscribing derives from SttService.job.state), so push it
    // explicitly — the IDE swaps center-pulse → traveling wave on it.
    onSttIsTranscribingChanged: {
        if (_sttTargetTerminalPid > 0) _pushSttState();
    }

    /// Check if a single agent matches the current STT injection target.
    /// Used by ProjectGroup.hasSttTarget and AgentChip.isSttTarget to avoid duplication.
    function isAgentSttTarget(agent: var): bool {
        if (sttTargetTerminalPid <= 0) return false;
        if ((agent.terminal_pid ?? 0) !== sttTargetTerminalPid) return false;
        if (sttTargetBufId === -1) return agent.active ?? false;
        return (agent.buf ?? -1) === sttTargetBufId;
    }

    // ── Desktop notifications ────────────────────────────────────────
    // Notification messages arrive from the bridge pre-enriched with project
    // and terminal_pid. We add workspace info from _workspaceMap and spawn
    // notify-send. This replaces the old claude-notify.sh shell script.

    // Backend-specific notification icons — mirror the agentbar identities
    // (Claude sparkle vs OpenCode 3×3 grid) so a glance at a popup says which
    // agent it came from. _notifIconFor() picks by agent_type; absent/"" → Claude
    // (backward-compatible: pre-agent_type notifications and Claude agents).
    readonly property string _claudeNotifIcon: `${Paths.home}/.dotfiles/scripts/claude-icon.svg`
    readonly property string _openCodeNotifIcon: `${Paths.home}/.dotfiles/scripts/opencode-icon.svg`

    function _notifIconFor(agentType: string): string {
        return agentType === "opencode" ? root._openCodeNotifIcon : root._claudeNotifIcon;
    }

    function _handleNotification(notif: var): void {
        const project = notif.project ?? "unknown";
        const terminalPid = notif.terminal_pid ?? 0;
        const ws = _workspaceMap[terminalPid] ?? null;

        // Format workspace display (uses ws.name directly — O(1) dict lookup
        // vs workspaceIconForWsId's O(N) linear search through Hypr.workspaces)
        let wsDisplay = "";
        if (ws) {
            wsDisplay = ws.name.startsWith("special:")
                ? `[${ws.name.slice(8)}]`
                : `[WS ${ws.name}]`;
        }

        // Build title: "Agent [project] [WS III] - Ready"
        const titleParts = ["Agent", `[${project}]`];
        if (wsDisplay) titleParts.push(wsDisplay);
        titleParts.push("-", notif.title_suffix ?? notif.event);
        const title = titleParts.join(" ");

        const message = notif.message ?? "";
        const urgency = notif.urgency ?? "normal";
        const agentType = notif.agent_type ?? "";

        Logger.log("qml", "agent", `notify | title="${title}" msg="${message}" urgency=${urgency} type=${agentType || "claude"}`);
        _sendNotification(title, message, urgency, agentType);
    }

    function _sendNotification(title: string, message: string, urgency: string, agentType: string): void {
        // App name AND icon both track the backend: the notification center groups
        // by app name (Notifs.closeGroup), so a distinct name keeps OpenCode and
        // Claude popups in separate stacks, each showing its own glyph. Empty/
        // unknown agentType falls back to Claude — see _notifIconFor.
        const appName = agentType === "opencode" ? "OpenCode" : "Claude Code";
        Quickshell.execDetached([
            "notify-send",
            `--app-name=${appName}`,
            `--urgency=${urgency}`,
            `--icon=${root._notifIconFor(agentType)}`,
            "--expire-time=15000",
            title,
            message,
        ]);
    }

    // TODO: Add activityText(agent) for future tooltip in ProjectGroup / agent dashboard.
    // Would map activity_state + activity_tool to human-readable strings.

    /// Find the currently active agent for a terminal PID. Returns the agent that is
    /// currently active (via representativeAgent) among those matching the PID, or null.
    function activeAgentForTerminal(terminalPid: int): var {
        if (terminalPid <= 0) return null;
        const matching = _agents.filter(a => a.terminal_pid === terminalPid);
        if (matching.length === 0) return null;
        return representativeAgent(matching);
    }

    /// Resolve the agent's Neovim RPC socket path.
    /// Prefers the real socket (v:servername) reported by the orchestrator's
    /// hello message and forwarded by the bridge — authoritative for
    /// embedding hosts that pass an explicit --listen path (Symmetria IDE
    /// uses /tmp/symmetria-nvim-*/nvim.sock, where the pid-derived guess
    /// below does not exist). Falls back to nvim's default servername
    /// pattern (/run/user/$UID/nvim.<nvim_pid>.0) for agents registered
    /// before the bridge forwarded nvim_socket.
    function nvimSocketForAgent(agent: var): string {
        if (!agent || !agent.nvim_pid) return "";
        if (agent.nvim_socket) return agent.nvim_socket;
        const runtimeDir = Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000";
        return `${runtimeDir}/nvim.${agent.nvim_pid}.0`;
    }

    // TODO [Level 2]: Add injectText(text: string, submit: bool) method that:
    // 1. Uses nvimSocketForAgent() to resolve socket
    // 2. Calls orchestrator.stt_inject() via Neovim RPC
    // 3. Falls back to sendshortcut paste if no agent match
    // This would make AgentService the injection middleman, replacing
    // SttService's direct stt-inject.sh calls.

    // Debounce timer for workspace map rebuilds (100ms)
    Timer {
        id: wsRebuildDebounce
        interval: 100
        onTriggered: root._rebuildWorkspaceMap()
    }

    // Events that affect window-to-workspace mapping (Set for O(1) lookup)
    // intentional var: JS Set — no QML equivalent for O(1) .has() lookups
    readonly property var _wsLayoutEvents: new Set([
        "movewindow", "movewindowv2", "openwindow", "closewindow", "activespecial",
        "renameworkspace"
    ])

    // Listen to Hyprland events that affect window-to-workspace mapping
    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (root._wsLayoutEvents.has(event.name))
                wsRebuildDebounce.restart();
        }
    }

    Component.onCompleted: {
        Logger.log("qml", "agent", `init | enabled=${Config.agentbar.enabled}`);
        if (Config.agentbar.enabled)
            _startBridge();
    }

    Component.onDestruction: {
        if (bridgeProcess.running)
            bridgeProcess.running = false;
    }

    /// Apply a parsed bridge state update to agent/project properties.
    function _applyBridgeUpdate(parsed: var): void {
        const prevCount = root._agents.length;
        const nextAgents = parsed.agents ?? [];

        // Diff and log activity state changes — pairs with bridge's "activity |" line.
        _logAgentStateDiff(root._agents, nextAgents);

        root._agents = nextAgents;
        root._projects = parsed.projects ?? [];
        // Start the backoff reset timer once (not restart!) — it fires after 10s
        // of the bridge being alive, regardless of data flow. Using .restart()
        // would push the timer out on every RECV, and since activity updates
        // arrive every 3-5s, the timer would never fire.
        if (!backoffResetTimer.running)
            backoffResetTimer.start();
        Logger.log("qml", "agent", `recv | agents=${root._agents.length} projects=${root._projects.length} prev=${prevCount}`);
    }

    /// Log per-agent activity_state changes between prevAgents and nextAgents.
    /// Pairs with bridge's "activity |" line to confirm UI-side propagation.
    /// Also updates _stateEnteredAt so the QML-side stuck watchdog can
    /// detect any agent that has held a non-idle state for too long even
    /// when the bridge process is silent.
    function _logAgentStateDiff(prevAgents: var, nextAgents: var): void {
        // Build prev-state lookup using a Set to track seen IDs — avoids
        // 'delete obj.prop' which de-optimizes V8 hidden class (project-standards P0).
        const prevStateById = {};
        for (const a of prevAgents) prevStateById[a.id] = a.activity_state ?? "";

        const seenIds = new Set();
        const now = Date.now();
        for (const a of nextAgents) {
            seenIds.add(a.id);
            const prev = prevStateById[a.id] ?? "";
            const curr = a.activity_state ?? "";
            if (prev !== curr) {
                Logger.log("qml", "agent",
                    `state | ${a.id} ${prev || "-"}→${curr || "-"} tool=${a.activity_tool || "-"} plan=${a.in_plan_mode === true}`);
                root._stateEnteredAt[a.id] = now;
                root._stuckWarned.delete(a.id);
            } else if (!(a.id in root._stateEnteredAt)) {
                // First sighting of this agent — record the entry time so
                // the stuck watchdog has a reference even if no transition
                // ever follows (e.g., bridge restart leaves us already in
                // "working").
                root._stateEnteredAt[a.id] = now;
            }
        }
        // Anything left in prevStateById that wasn't seen disappeared from
        // the new set. We deliberately do NOT delete the entry from
        // _stateEnteredAt: V8 de-optimizes hash maps that get keys deleted
        // (project standard P0). A stale entry is harmless — it'll be
        // overwritten on the agent's next sighting, and the key set is
        // bounded by the lifetime of all agent_ids in this shell session.
        for (const aid in prevStateById) {
            if (!seenIds.has(aid)) {
                const prev = prevStateById[aid];
                if (prev) Logger.log("qml", "agent", `state | ${aid} ${prev}→removed`);
                root._stuckWarned.delete(aid);
            }
        }
    }

    // ── Stuck-state watchdog (QML side) ─────────────────────────────────
    // Mirrors the bridge-side check_stuck_working() but observes from the
    // rendering layer. Catches the case where the bridge has up-to-date
    // state but QML missed an emission, AND surfaces the symptom directly
    // in the QML log so it interleaves with rendering events.

    // {agent_id: ms-since-epoch when this agent's current state began}
    // intentional var: JS object used as hash map (string → number)
    property var _stateEnteredAt: ({})
    // Set of agent_ids we've already warned about; cleared on transition.
    // intentional var: JS Set — no QML equivalent for .has()/.delete()
    property var _stuckWarned: new Set()
    // Threshold for warning (ms). Mirrors bridge STUCK_WORKING_WARN_SECONDS.
    readonly property int _stuckWorkingWarnMs: 120 * 1000

    Timer {
        id: stuckWatchdog
        interval: 30 * 1000  // Check every 30s
        running: Config.agentbar.enabled
        repeat: true

        onTriggered: {
            const now = Date.now();
            for (const a of root._agents) {
                const state = a.activity_state ?? "";
                if (state !== "working") continue;
                const entered = root._stateEnteredAt[a.id] ?? now;
                const stuckFor = now - entered;
                if (stuckFor < root._stuckWorkingWarnMs) continue;
                if (root._stuckWarned.has(a.id)) continue;
                root._stuckWarned.add(a.id);
                Logger.log("qml", "agent",
                    `STUCK WORKING | ${a.id} project=${a.project} tool=${a.activity_tool || "-"} stuck_for=${Math.round(stuckFor / 1000)}s`);
            }
        }
    }

    /// Build a JSON-serializable snapshot of QML-side agent state for
    /// diagnostic dumps. Mirrors the bridge's diagnostic dump but from the
    /// rendering layer's perspective so we can compare and find drift.
    function diagnosticSnapshot(): var {
        const now = Date.now();
        return {
            ts: new Date().toISOString(),
            agentCount: root._agents.length,
            projects: root._projects,
            mergeActive: root.mergeActive,
            userHidden: root.userHidden,
            bridgeRunning: root.bridgeRunning,
            agents: root._agents.map(a => ({
                id: a.id,
                project: a.project,
                state: a.activity_state ?? "",
                tool: a.activity_tool ?? "",
                in_plan_mode: a.in_plan_mode === true,
                active: a.active === true,
                remote: a.remote === true,
                terminal_pid: a.terminal_pid ?? 0,
                state_age_ms: now - (root._stateEnteredAt[a.id] ?? now),
                warned_stuck: root._stuckWarned.has(a.id),
            })),
        };
    }

    function _startBridge(): void {
        if (bridgeProcess.running) {
            Logger.log("qml", "agent", "start | already running, skipping");
            return;
        }
        Logger.log("qml", "agent", `start | launching ${_bridgeScript}`);
        bridgeProcess.command = ["python3", _bridgeScript];
        bridgeProcess.running = true;
    }

    // Bridge process — long-running, writes JSON lines to stdout
    Process {
        id: bridgeProcess

        // stdin carries shell→hub control lines (stt_state pushes via
        // _pushSttState). Without this flag, Process.write() is a no-op.
        stdinEnabled: true

        stdout: SplitParser {
            onRead: data => {
                const text = data.trim();
                if (!text) return;
                try {
                    const parsed = JSON.parse(text);

                    // Notification messages bypass throttle — always immediate
                    if (parsed.type === "notification") {
                        root._handleNotification(parsed);
                        return;
                    }

                    // Leading-edge + buffer throttle: first update applies
                    // immediately, subsequent updates within the 100ms cooldown
                    // are buffered (only latest kept — full state, not diff).
                    if (!root._throttleActive) {
                        // Leading edge — apply immediately + start cooldown
                        root._applyBridgeUpdate(parsed);
                        root._throttleActive = true;
                        bridgeThrottle.restart();
                    } else {
                        // During cooldown — buffer latest (discard intermediate)
                        root._pendingUpdate = parsed;
                    }
                } catch (e) {
                    Logger.log("qml", "agent", `parse-error | ${text.slice(0, 200)}`);
                }
            }
        }

        onExited: (code, status) => {
            Logger.log("qml", "agent", `bridge-exit | code=${code} status=${status} hadAgents=${root._agents.length}`);
            // Clear state on exit (including throttle state)
            root._agents = [];
            root._projects = [];
            root._pendingUpdate = null;
            root._throttleActive = false;
            bridgeThrottle.stop();
            backoffResetTimer.stop();

            if (!Config.agentbar.enabled) {
                Logger.log("qml", "agent", "bridge-exit | agentbar disabled, not restarting");
                return;
            }

            // Restart with exponential backoff (capped at _maxRestartDelay)
            const delay = Math.min(1000 * Math.pow(2, root._restartCount), root._maxRestartDelay);
            // Cap _restartCount to prevent unbounded growth (2^10 = 1024s, well past 30s cap)
            root._restartCount = Math.min(root._restartCount + 1, 10);
            Logger.log("qml", "agent", `bridge-restart | code=${code} delayMs=${delay} attempt=${root._restartCount}`);
            restartTimer.interval = delay;
            restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer
        onTriggered: root._startBridge()
    }

    // Trailing edge of state-update throttle: apply buffered update if any,
    // otherwise clear the cooldown so the next update gets leading-edge treatment.
    Timer {
        id: bridgeThrottle
        interval: 100

        onTriggered: {
            if (root._pendingUpdate !== null) {
                const update = root._pendingUpdate;
                root._pendingUpdate = null;
                root._applyBridgeUpdate(update);
                // Re-arm cooldown in case more updates arrive during apply
                bridgeThrottle.restart();
            } else {
                root._throttleActive = false;
            }
        }
    }

    // Only reset backoff after the bridge has been running stably for 10 seconds.
    // This prevents crash-on-init loops from resetting the counter prematurely.
    Timer {
        id: backoffResetTimer
        interval: 10000
        onTriggered: {
            root._restartCount = 0;
            Logger.log("qml", "agent", "bridge-stable | backoff reset after 10s");
        }
    }

    IpcHandler {
        target: "agentbar"

        function status(): string {
            return JSON.stringify({
                agents: root.agentCount,
                projects: root.sortedProjects,
                bridgeRunning: root.bridgeRunning,
                userHidden: root.userHidden,
                mergeActive: root.mergeActive,
            });
        }

        /// Full per-agent diagnostic snapshot: state, tool, age, stuck flags.
        /// Pair with bridge-side dump (SIGUSR1) for end-to-end pipeline view.
        ///
        /// Usage:
        ///   symmetria shell agentbar diagnose
        ///   pkill -USR1 -f agent-bridge.py  # then read the bridge JSON
        function diagnose(): string {
            const snap = root.diagnosticSnapshot();
            Logger.log("qml", "agent", `diagnose | ${JSON.stringify(snap)}`);
            return JSON.stringify(snap, null, 2);
        }

        /// Log a user report that a specific agent is stuck. Use this as the
        /// user-controlled escape hatch for the "stuck on working" symptom —
        /// it records the complaint in the log so we can grep for the exact
        /// moment the user noticed, and emits a full diagnostic snapshot for
        /// correlation with the bridge's SIGUSR1 dump.
        ///
        /// NOTE: This does NOT actually clear the stuck state. The bridge does
        /// not accept clear messages from arbitrary clients. A proper IPC verb
        /// is future work. Until then, the log record is the entire action.
        function reportStuck(agentId: string): void {
            Logger.log("qml", "agent", `report-stuck | user reports ${agentId} stuck — full snapshot to follow`);
            Logger.log("qml", "agent", `report-stuck-snap | ${JSON.stringify(root.diagnosticSnapshot())}`);
        }

        function toggle(): void {
            if (root.agentCount === 0) return;
            root._userHidden = !root._userHidden;
        }

        function show(): void {
            root._userHidden = false;
        }

        function hide(): void {
            root._userHidden = true;
        }

        function merge(): void {
            Config.agentbar.mergeWorkspaces = true;
        }

        function unmerge(): void {
            Config.agentbar.mergeWorkspaces = false;
        }

        function togglemerge(): void {
            Config.agentbar.mergeWorkspaces = !Config.agentbar.mergeWorkspaces;
        }
    }
}
