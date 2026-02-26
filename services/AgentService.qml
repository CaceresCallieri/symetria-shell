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

    /// Whether the bridge process is alive (does NOT mean the socket is ready —
    /// there is a ~50-100ms startup window before the asyncio server binds).
    readonly property bool bridgeRunning: bridgeProcess.running

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

    /// Pick representative workspace for a group of agents:
    /// active agent's workspace, or first agent's workspace.
    function workspaceForAgents(agents: var): var {
        if (!agents || agents.length === 0) return null;
        const active = agents.find(a => a.active);
        return root.workspaceForAgent(active ?? agents[0]);
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

    // Debounce timer for workspace map rebuilds (100ms)
    Timer {
        id: wsRebuildDebounce
        interval: 100
        onTriggered: root._rebuildWorkspaceMap()
    }

    // Events that affect window-to-workspace mapping (Set for O(1) lookup)
    readonly property var _wsLayoutEvents: new Set([
        "movewindow", "movewindowv2", "openwindow", "closewindow", "activespecial"
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
                projects: root.projects,
                bridgeRunning: root.bridgeRunning,
            });
        }
    }
}
