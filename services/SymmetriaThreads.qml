pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import Symmetria

/// Mesura Code's projects and threads, read from its own Unix socket.
///
/// The bar's only source. It was built as a SIBLING of AgentService rather than
/// a feeder into it, because Symmetria IDE and its `agent-bridge.py` hub were
/// always meant to be temporary and the seam had to survive their deletion. That
/// deletion has happened: `AgentBarContent` no longer unions two sources, and
/// every join onto a local Hyprland window went with the IDE.
///
/// AgentService still exists, reduced to dictation plumbing on its way out.
/// Nothing here reads it and nothing in it reads this — keep it that way.
///
/// ## The socket is discovered, not addressed
///
/// Mesura names its socket with its own pid, the way the dictation one is
/// named. The shell knows the pid there because `SttJob` starts from a target
/// WINDOW; the bar has no such context, so it looks the socket up instead.
/// `discoverProcess` lists the runtime directory and takes the NEWEST match —
/// one shot per connection attempt, not a pipe held open.
///
/// Newest rather than first, because a Unix socket file outlives the process
/// that bound it when that process is killed rather than stopped. Sorting
/// lexicographically would let a stale socket from a crashed instance shadow a
/// live one forever whenever its pid happened to sort earlier; sorting by
/// modification time picks the most recently started Mesura instead. It is not
/// a liveness check — connecting is — but it makes the common stale case
/// self-correcting.
///
/// ## Reconnection is the ordinary case
///
/// Mesura may not be running when the shell starts, may be restarted under it,
/// and may be quit for the day. None of those is an error worth surfacing: the
/// bar simply shows nothing from this source. The retry backs off so a machine
/// with Mesura permanently absent is not listing a directory every second
/// forever.
Singleton {
    id: root

    /// Array of `{ project: string, agents: array }`, the shape ProjectGroup
    /// consumes. Empty whenever nothing is connected.
    readonly property var projectGroups: root._groupsFrom(root._threads, root._projects)

    // ── Stream state ───────────────────────────────────────────────────
    // Mirrors the contract's own consumer semantics: a stream opens with a
    // snapshot, a delta must sit at exactly `revision + 1`, and a gap is
    // reported rather than repaired. There is no buffering and no reordering
    // here for the same reason the contract forbids them — a gap that resolves
    // itself by waiting is the consumer inferring a missing event from a local
    // timeout.
    property var _threads: ({})   // threadId -> thread summary
    property var _projects: ({})  // projectId -> project summary
    property int _revision: -1
    property string _socketPath: ""

    readonly property int _protocolMajor: 1

    function _groupsFrom(threads: var, projects: var): var {
        const byProject = {};
        for (const key in threads) {
            const thread = threads[key];
            const name = projects[thread.projectId]?.name ?? "";
            // A thread whose project has not arrived yet is held back rather
            // than grouped under its raw identifier. The pill's whole content
            // is the name, so an id there would read as a bug on screen; the
            // project's own delta lands in the same batch or the next one.
            if (!name)
                continue;
            if (!byProject[name])
                byProject[name] = [];
            byProject[name].push(root._asAgent(thread, name));
        }
        return Object.keys(byProject).map(name => ({
                    project: name,
                    agents: byProject[name]
                }));
    }

    /// Shapes one thread as the bar's chip expects an agent.
    ///
    /// `agent_type` is left EMPTY deliberately. AgentChip reads it to pick
    /// between the Claude sparkle and the OpenCode grid, and falls back to
    /// Claude for anything it does not recognise — which is the decided v1
    /// behaviour for every Mesura thread, whichever provider actually backs it.
    /// The wire cannot say: the projection excludes provider identity by
    /// design. Tracked as mesura-code issue #15; do not infer a provider from
    /// anything else here.
    function _asAgent(thread: var, projectName: string): var {
        const running = thread.session?.status === "running";
        return {
            // Namespaced, because bridge agents and these threads are
            // concatenated into ONE ScriptModel keyed on `id`. The two id
            // spaces are defined by different systems and nothing guarantees
            // they stay disjoint; a collision would silently make one row
            // render the other's data. A prefix makes it structurally
            // impossible rather than merely unlikely.
            id: "mesura:" + thread.threadId,
            project: projectName,
            title: thread.title ?? "",
            // The vocabulary AgentChip branches on. Only the busy/idle
            // distinction is expressed in v1; "working" is one of the four
            // states its `_isBusyState` accepts.
            activity_state: running ? "working" : "",
            activity_tool: "",
            agent_type: "",
            active: false,
            remote: false,
            // No local window, and therefore no workspace and no terminal to
            // focus. The bar used to join on this pid for a workspace badge, a
            // focused-pill highlight and click-to-focus; all three went out with
            // Symmetria IDE, because a Mesura thread could never satisfy them.
            // The field stays because it is part of the row shape the chips read.
            terminal_pid: 0
        };
    }

    function _reset(): void {
        root._threads = ({});
        root._projects = ({});
        root._revision = -1;
    }

    function _applySnapshot(item: var): void {
        if (item.protocolVersion?.major !== root._protocolMajor) {
            Logger.log("qml", "mesura", `protocol-mismatch | major=${item.protocolVersion?.major}`);
            root._reset();
            return;
        }
        const threads = {};
        for (const thread of item.threads ?? [])
            threads[thread.threadId] = thread;
        const projects = {};
        for (const project of item.projects ?? [])
            projects[project.projectId] = project;
        root._threads = threads;
        root._projects = projects;
        root._revision = item.revision ?? 0;
    }

    function _applyDelta(item: var): void {
        // A stream that has not opened cannot fold a delta into a world it
        // never received. Dropping it and waiting for the snapshot is right:
        // the producer sends one on every connection.
        if (root._revision < 0)
            return;

        if (item.sequence !== root._revision + 1) {
            // A gap. The contract offers exactly one recovery and it is not
            // waiting: reopen and take a fresh snapshot.
            Logger.log("qml", "mesura", `gap | at=${root._revision} got=${item.sequence}`);
            root._reset();
            // Dropping the connection is the whole recovery: `reconnect.running`
            // is BOUND to `!sock.connected`, so the timer starts itself. Calling
            // `restart()` here would write that bound property and sever the
            // binding for the life of the process — after which the timer never
            // stops again, and only the guard in `onTriggered` keeps the extra
            // ticks harmless. Review caught it working by accident.
            sock.connected = false;
            return;
        }

        const change = item.change ?? {};
        if (change.entity === "thread" && change.thread) {
            const threads = Object.assign({}, root._threads);
            threads[change.thread.threadId] = change.thread;
            root._threads = threads;
        } else if (change.entity === "project" && change.project) {
            const projects = Object.assign({}, root._projects);
            projects[change.project.projectId] = change.project;
            root._projects = projects;
        }
        // Any other entity is one this build does not read — surfaces and
        // drafts among them. The position is still consumed, which is the
        // whole point of the contract's unknown-change member: skipping one
        // update costs less than the resnapshot that refusing it would force.
        root._revision = item.sequence;
    }

    function _onLine(line: string): void {
        const text = line.trim();
        if (!text)
            return;
        let item;
        try {
            item = JSON.parse(text);
        } catch (e) {
            Logger.log("qml", "mesura", `parse-error | ${text.slice(0, 120)}`);
            return;
        }
        if (item.type === "snapshot")
            root._applySnapshot(item);
        else if (item.type === "delta")
            root._applyDelta(item);
    }

    Socket {
        id: sock

        path: root._socketPath
        connected: false

        parser: SplitParser {
            onRead: data => root._onLine(data)
        }

        onConnectionStateChanged: {
            if (connected) {
                Logger.log("qml", "mesura", `attached | ${root._socketPath}`);
                reconnect.interval = 1000;
            } else {
                Logger.log("qml", "mesura", "detached");
                root._reset();
                // No `restart()` here either, and for the same reason: the
                // binding on `running` has already started the timer by the
                // time this handler runs.
            }
        }
    }

    /// Lists the runtime directory for Mesura's socket. One shot per attempt.
    Process {
        id: discoverProcess

        command: ["sh", "-c", "ls -1t \"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}\"/symmetria-mesura-threads-*.sock 2>/dev/null | head -1"]

        stdout: SplitParser {
            onRead: data => {
                const found = data.trim();
                if (!found)
                    return;
                root._socketPath = found;
                sock.connected = true;
            }
        }
    }

    Timer {
        id: reconnect

        interval: 1000
        repeat: true
        running: !sock.connected

        onTriggered: {
            if (sock.connected)
                return;
            // Backs off to a minute. A machine where Mesura is simply not
            // installed should not list a directory every second forever, and
            // a minute is well inside the patience of somebody who just
            // launched it.
            interval = Math.min(interval * 2, 60000);
            if (!discoverProcess.running)
                discoverProcess.running = true;
        }
    }

    Component.onCompleted: discoverProcess.running = true
}
