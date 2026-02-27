pragma Singleton

import qs.config
import qs.services
import qs.utils
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

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
    readonly property var agents: _agents
    readonly property var projects: _projects
    readonly property int agentCount: _agents.length

    /// Projects sorted by workspace: named (left) → normal 1-10 (middle) → special (right).
    /// Depends on _projects, _agents, _workspaceMap so it re-sorts when any change.
    readonly property var sortedProjects: _sortProjectsByWorkspace(_projects, _agents, _workspaceMap)

    /// Whether the bridge process is alive (does NOT mean the socket is ready —
    /// there is a ~50-100ms startup window before the asyncio server binds).
    readonly property bool bridgeRunning: bridgeProcess.running

    // ── STT target tracking ────────────────────────────────────────────
    // Set by SttService at recording start; cleared on idle/cancel.
    // ProjectGroup reads these to show a red border on the targeted pill.
    readonly property int sttTargetTerminalPid: _sttTargetTerminalPid
    readonly property int sttTargetBufId: _sttTargetBufId  // -1 = representative agent

    // Internal state — always reassigned (never mutated in-place) so QML
    // bindings on agents/agentCount fire correctly. Do not use .push()/.splice().
    property var _agents: []
    property var _projects: []
    property int _restartCount: 0
    readonly property int _maxRestartDelay: 30000

    // Resolve script path relative to this QML file
    // Qt.resolvedUrl returns "file:///abs/path" on Linux; strip "file://" to get "/abs/path"
    readonly property string _bridgeScript: Qt.resolvedUrl("../scripts/agent-bridge.py").toString().replace(/^file:\/\//, "")

    // M3 palette for agent dot colors (8 colors matching orchestrator's palette)
    readonly property var palette: [
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

    /// Resolve workspace to display icon, matching the workspace bar's chain:
    /// special ws → getSpecialWsIcon, named ws → getNamedWsIcon, numbered → romanize
    function workspaceIconForWsId(wsId: int): string {
        // Look up workspace object from Hyprland for name-based resolution
        const ws = Hypr.workspaces.values.find(w => w.id === wsId) ?? null;

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
    }

    /// Clear the STT target highlight. Called by SttService on cancel/idle.
    function clearSttTarget(): void {
        _sttTargetTerminalPid = -1;
        _sttTargetBufId = -1;
    }

    /// Find the matching agent for a terminal PID. Returns agent object or null.
    function agentForTerminal(terminalPid: int): var {
        if (terminalPid <= 0) return null;
        const matching = _agents.filter(a => a.terminal_pid === terminalPid);
        if (matching.length === 0) return null;
        return representativeAgent(matching);
    }

    /// Derive Neovim socket path from agent's nvim_pid.
    /// Pattern: /run/user/$UID/nvim.<nvim_pid>.0
    function nvimSocketForAgent(agent: var): string {
        if (!agent || !agent.nvim_pid) return "";
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
        console.log("[AgentService] INIT: agentbar.enabled =", Config.agentbar.enabled);
        if (Config.agentbar.enabled)
            _startBridge();
    }

    Component.onDestruction: {
        if (bridgeProcess.running)
            bridgeProcess.running = false;
    }

    function _startBridge(): void {
        if (bridgeProcess.running) {
            console.log("[AgentService] _startBridge: already running, skipping");
            return;
        }
        console.log("[AgentService] _startBridge: launching", _bridgeScript);
        bridgeProcess.command = ["python3", _bridgeScript];
        bridgeProcess.running = true;
    }

    // Bridge process — long-running, writes JSON lines to stdout
    Process {
        id: bridgeProcess

        stdout: SplitParser {
            onRead: data => {
                const text = data.trim();
                if (!text) return;
                try {
                    const parsed = JSON.parse(text);
                    const prevCount = root._agents.length;
                    root._agents = parsed.agents ?? [];
                    root._projects = parsed.projects ?? [];
                    // Debounced backoff reset: only clear _restartCount after the
                    // bridge has been running stably for 10s. This prevents a
                    // crash-on-init loop from defeating exponential backoff (a
                    // bridge that emits one line then crashes would reset the
                    // counter immediately without this guard).
                    backoffResetTimer.restart();
                    console.log(`[AgentService] RECV: ${root._agents.length} agents, ${root._projects.length} projects (was ${prevCount})`);
                } catch (e) {
                    console.warn("[AgentService] Failed to parse bridge output:", text);
                }
            }
        }

        onExited: (code, status) => {
            console.log(`[AgentService] BRIDGE EXITED: code=${code}, status=${status}, had ${root._agents.length} agents`);
            // Clear state on exit
            root._agents = [];
            root._projects = [];
            backoffResetTimer.stop();

            if (!Config.agentbar.enabled) {
                console.log("[AgentService] agentbar disabled, not restarting");
                return;
            }

            // Restart with exponential backoff (capped at _maxRestartDelay)
            const delay = Math.min(1000 * Math.pow(2, root._restartCount), root._maxRestartDelay);
            // Cap _restartCount to prevent unbounded growth (2^10 = 1024s, well past 30s cap)
            root._restartCount = Math.min(root._restartCount + 1, 10);
            console.warn(`[AgentService] Bridge exited (code ${code}), restarting in ${delay}ms (attempt #${root._restartCount})`);
            restartTimer.interval = delay;
            restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer
        onTriggered: root._startBridge()
    }

    // Only reset backoff after the bridge has been running stably for 10 seconds.
    // This prevents crash-on-init loops from resetting the counter prematurely.
    Timer {
        id: backoffResetTimer
        interval: 10000
        onTriggered: {
            root._restartCount = 0;
            console.log("[AgentService] Bridge stable for 10s, backoff reset");
        }
    }

    IpcHandler {
        target: "agentbar"

        function status(): string {
            return JSON.stringify({
                agents: root.agentCount,
                projects: root.sortedProjects,
                bridgeRunning: root.bridgeRunning,
            });
        }
    }
}
