pragma Singleton

import qs.config
import qs.services
import Quickshell
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
    readonly property bool connected: bridgeProcess.running

    // Internal state — always reassigned (never mutated in-place) so QML
    // bindings on agents/agentCount fire correctly. Do not use .push()/.splice().
    property var _agents: []
    property var _projects: []
    property int _restartCount: 0
    readonly property int _maxRestartDelay: 30000

    // Resolve script path relative to this QML file
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
                    root._restartCount = 0;  // Reset backoff on successful data
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

            if (!Config.agentbar.enabled) {
                console.log("[AgentService] agentbar disabled, not restarting");
                return;
            }

            // Restart with exponential backoff
            const delay = Math.min(1000 * Math.pow(2, root._restartCount), root._maxRestartDelay);
            root._restartCount++;
            console.warn(`[AgentService] Bridge exited (code ${code}), restarting in ${delay}ms (attempt #${root._restartCount})`);
            restartTimer.interval = delay;
            restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer
        onTriggered: root._startBridge()
    }

    IpcHandler {
        target: "agentbar"

        function status(): string {
            return JSON.stringify({
                agents: root.agentCount,
                projects: root.projects,
                connected: root.connected
            });
        }
    }
}
