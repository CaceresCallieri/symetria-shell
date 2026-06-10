#!/usr/bin/env python3
"""Symmetria Agent Bridge — aggregates orchestrator.nvim state via Unix socket.

Accepts connections from multiple Neovim/orchestrator instances, each sending
JSON-line messages about their Claude Code agents. Maintains a consolidated
view and writes it to stdout on every state change for Symmetria's QML
AgentService to consume via Process + SplitParser.

Socket: /run/user/$UID/symmetria-agents.sock
Protocol: JSON lines (newline-delimited JSON) in both directions.
"""

import asyncio
import atexit
import json
import os
import signal
import subprocess
import sys
import time
from collections import deque
from datetime import datetime
from pathlib import Path

SOCKET_PATH = Path(os.environ.get(
    "SYMMETRIA_AGENT_SOCKET",
    f"/run/user/{os.getuid()}/symmetria-agents.sock",
))

# Seconds before an orphaned activity entry (no live orchestrator connection)
# is reaped. Registered agents are NOT reaped by timeout — Claude Code can
# legitimately go silent for minutes during long thinking/planning phases
# where no hook events fire. Use manual assertion (orchestrator keybind)
# to force-check agent liveness instead.
ACTIVITY_STALENESS_TIMEOUT = 15

# Stuck-state watchdog threshold. If an agent stays in "working" for longer
# than this without any state transition, the watchdog logs a warning. This
# is purely observational — it does NOT clear the state. Real recovery is
# the orchestrator's quiet_bufs liveness path.
STUCK_WORKING_WARN_SECONDS = 120

# How many activity transitions to retain per agent for postmortem dumps.
# 20 is enough to cover the trailing PreToolUse → PostToolUse → Stop dance
# of a typical Claude Code turn, plus several preceding tool calls.
ACTIVITY_HISTORY_DEPTH = 20

# Diagnostic dump path written on SIGUSR1. Captures full bridge state +
# per-agent history so a stuck-state symptom can be analyzed offline.
DIAGNOSTIC_DUMP_PATH = Path(
    os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state"
) / "symmetria" / "agent-bridge-diagnostic.json"

# Inode of the socket we created — used to avoid deleting a newer process's socket
_our_socket_inode: int | None = None

# Unified log shared with Symmetria.Logger (C++), QML services, and bash
# scripts. Format: "HH:MM:SS.mmm [py:bridge] message". Path resolution and
# format match plugin/src/Symmetria/logger.cpp so all sources interleave
# in a single timeline.
_LOG_LEVELS = {"DEBUG": 0, "INFO": 1, "WARNING": 2, "WARN": 2, "ERROR": 3}
_LOG_LEVEL = _LOG_LEVELS.get(os.environ.get("AGENT_BRIDGE_LOG_LEVEL", "INFO").upper(), 1)
_LOG_PATH = Path(os.environ["SYMMETRIA_DEBUG_LOG"]) if os.environ.get("SYMMETRIA_DEBUG_LOG") \
    else Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state") / "symmetria" / "debug.log"
try:
    _LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
except OSError:
    pass  # Log directory creation failure must not crash the bridge


def _emit_log(level: int, msg: str) -> None:
    if level < _LOG_LEVEL:
        return
    now = datetime.now()
    ts = f"{now.strftime('%H:%M:%S')}.{now.microsecond // 1000:03d}"
    line = f"{ts} [py:bridge] {msg}\n"
    try:
        with open(_LOG_PATH, "a") as f:
            f.write(line)
    except OSError:
        pass


class _Log:
    def debug(self, fmt, *args): _emit_log(0, fmt % args if args else fmt)
    def info(self, fmt, *args): _emit_log(1, fmt % args if args else fmt)
    def warning(self, fmt, *args): _emit_log(2, fmt % args if args else fmt)
    def error(self, fmt, *args): _emit_log(3, fmt % args if args else fmt)


log = _Log()


class AgentBridge:
    """Aggregates agent state from all connected orchestrator instances."""

    # Terminal emulator process names to match when walking /proc upward.
    TERMINAL_NAMES = frozenset({
        "ghostty", "kitty", "alacritty", "foot", "wezterm-gui",
        "konsole", "gnome-terminal", "xfce4-terminal", "xterm",
        "terminator", "tilix", "sakura", "st", "urxvt",
    })
    # Message types that carry per-client state mutations — used to detect
    # desync (message from unregistered pid) and trigger resolicit recovery.
    _DESYNC_TYPES: frozenset[str] = frozenset({"updated", "removed", "focus", "liveness", "added"})

    def __init__(self):
        # {nvim_pid: {buf: instance_data, ...}}
        self._clients: dict[int, dict[int, dict]] = {}
        # {nvim_pid: terminal_pid} — cached terminal PID per Neovim instance
        self._terminal_pids: dict[int, int] = {}
        # {nvim_pid: socket_path} — actual RPC socket (v:servername) reported
        # in the hello message. Authoritative over the pid-derived default
        # ($XDG_RUNTIME_DIR/nvim.<pid>.0), which is wrong for embedding hosts
        # that pass an explicit --listen path (Symmetria IDE).
        self._nvim_sockets: dict[int, str] = {}
        # nvim_pids from remote machines (PID doesn't exist in local /proc)
        self._remote_clients: set[int] = set()
        # {agent_id: {"state": str, "tool": str, "ts": float, "in_plan_mode": bool, "event_ts_ns": int}}
        # — activity state from hook scripts. event_ts_ns is the wall-clock
        # CLOCK_REALTIME nanosecond timestamp from the hook invocation, used
        # to detect out-of-order arrivals from async hooks racing over the
        # socket. ts is the bridge-side monotonic receipt time used for the
        # stuck-state watchdog and staleness reaping.
        self._activities: dict[str, dict] = {}
        # Per-agent backend identity ("claude" | "opencode"), reported by the
        # activity reporters (Claude hook / OpenCode plugin). Kept SEPARATE from
        # _activities because it's an IDENTITY, not an ephemeral state: when an
        # agent goes idle its _activities entry is popped, but its backend type
        # must persist so the dashboard keeps the right accent color. Cleared
        # only when the instance is fully torn down (_clear_agent_state).
        self._agent_types: dict[str, str] = {}
        # Per-agent ring buffer of recent state transitions for postmortem
        # diagnostics. Each entry: {ts, event_ts_ns, hook_event, state, tool,
        # ooo} where ooo is True if this update arrived out-of-order.
        self._activity_history: dict[str, deque] = {}
        # Per-agent set of warning flags we've already emitted (prevents spam).
        # Currently used for the stuck-working watchdog.
        self._warned_stuck: set[str] = set()
        # Per-parent-agent SubagentStart/Stop pairing counter. Increments on
        # SubagentStart, decrements on SubagentStop. Cleared on parent Stop.
        # An unpaired SubagentStop (count == 0) is the signature of Claude
        # Code's recap subagent: it spawns AFTER the parent's Stop fires, so
        # we never observed its SubagentStart. Such events are dropped
        # rather than letting them resurrect a cleared activity entry.
        self._subagent_depth: dict[str, int] = {}
        # Per-nvim_pid count of currently-open socket connections. The
        # orchestrator can briefly hold TWO parallel connections during
        # bridge restart (one from this bridge's RPC solicit, one from the
        # orchestrator's own auto-reconnect). When one of those closes, we
        # MUST NOT call remove_client() — the other connection is still
        # alive and depends on the registered state. remove_client only
        # fires when the count drops to zero (the last connection closes).
        # Without this, a 1ms-overlapping race during reconnect destroys
        # the agent for the entire bridge lifetime — the symptom is
        # "agent in project X never appears in the bar".
        self._conn_count: dict[int, int] = {}
        # Per-nvim_pid timestamp of the last reconnect solicitation. Used
        # to throttle the desync-recovery RPC: when an unregistered pid
        # sends us a state-mutation message, we ask its orchestrator to
        # re-send hello+sync. Without throttling, a still-alive but
        # unregistered orchestrator would trigger one RPC per message
        # (every ~1s for liveness/updated).
        self._last_resolicit: dict[int, float] = {}
        # Emit coalescing: leading-edge + trailing-edge with 50ms cooldown.
        # Prevents stdout floods during startup reconnect bursts (30+ events → 2 emissions).
        self._emit_handle: asyncio.TimerHandle | None = None
        self._emit_dirty: bool = False
        # Socket subscribers (e.g. the Symmetria IDE): StreamWriters registered
        # via a {"type": "subscribe"} message. Every consolidated snapshot that
        # goes to stdout is also written to each subscriber as the same JSON
        # line. Writes are fire-and-forget (no drain) so a slow or dead
        # subscriber can never stall the shell's stdout emission path —
        # _emit() runs in sync contexts (call_later callbacks) and cannot await.
        self._subscribers: set[asyncio.StreamWriter] = set()

    @staticmethod
    def _resolve_terminal_pid(nvim_pid: int) -> int:
        """Walk /proc upward from nvim_pid to find the terminal emulator PID.

        Reads /proc/{pid}/stat for each ancestor: field 2 is the comm name
        (in parens), field 4 is the parent PID.  If no terminal emulator is
        found before reaching PID 1 (nvim embedded in a non-terminal host
        like Symmetria IDE), falls back to the SYMMETRIA_HOST_WINDOW_PID
        variable the host exports into nvim's environment.  Returns 0 if
        both strategies fail.
        """
        pid = nvim_pid
        visited: set[int] = set()
        while pid > 1 and pid not in visited:
            visited.add(pid)
            try:
                stat = Path(f"/proc/{pid}/stat").read_text()
                # comm is in parens and may contain spaces: find the last ')'
                lparen = stat.index("(")
                rparen = stat.rindex(")")
                comm = stat[lparen + 1:rparen]
                if comm in AgentBridge.TERMINAL_NAMES:
                    log.debug("_resolve_terminal_pid: %d → %s (pid %d)", nvim_pid, comm, pid)
                    return pid
                # Field after closing paren: state ppid ...
                fields_after = stat[rparen + 2:].split()
                pid = int(fields_after[1])  # ppid is the 2nd field after ')'
            except (OSError, ValueError, IndexError):
                break
        host_pid = AgentBridge._host_window_pid_from_environ(nvim_pid)
        if host_pid:
            log.debug("_resolve_terminal_pid: %d → host window pid %d (environ)", nvim_pid, host_pid)
            return host_pid
        log.debug("_resolve_terminal_pid: %d → no terminal found", nvim_pid)
        return 0

    @staticmethod
    def _host_window_pid_from_environ(nvim_pid: int) -> int:
        """Read SYMMETRIA_HOST_WINDOW_PID from /proc/{nvim_pid}/environ.

        Embedding hosts that own a real compositor window but aren't terminal
        emulators (Symmetria IDE's QMLTermWidget panes) export their own PID
        under this variable before spawning nvim; the child inherits it.  The
        host PID is what Hyprland associates with the window, so resolving to
        it makes click-to-focus / workspace mapping / STT targeting work for
        embedded agents through the existing terminal_pid plumbing.  Returns
        0 when absent, malformed, or pointing at a dead process.
        """
        try:
            environ = Path(f"/proc/{nvim_pid}/environ").read_bytes()
            for entry in environ.split(b"\0"):
                if entry.startswith(b"SYMMETRIA_HOST_WINDOW_PID="):
                    host_pid = int(entry.partition(b"=")[2])
                    if host_pid > 0 and Path(f"/proc/{host_pid}").exists():
                        return host_pid
                    return 0
        except (OSError, ValueError):
            pass
        return 0

    @staticmethod
    def _is_remote_pid(nvim_pid: int) -> bool:
        """Check if nvim_pid is from a remote machine (process doesn't exist locally).

        Casts nvim_pid to int before path construction so a float JSON value (e.g.
        1234.0) doesn't produce a bogus path like /proc/1234.0 that never exists.

        Known false-negative: if a remote PID coincidentally matches a running local
        /proc entry, the client is treated as local. Negligible in practice given the
        large Linux PID space.
        """
        return not Path(f"/proc/{int(nvim_pid)}").exists()

    def _ensure_remote_detected(self, nvim_pid: int) -> None:
        """Add nvim_pid to _remote_clients if it doesn't exist in local /proc.

        Called on both hello and sync to handle normal connect and reconnect-after-
        bridge-restart paths (where hello may not have fired in the new session).
        """
        if self._is_remote_pid(nvim_pid):
            self._remote_clients.add(nvim_pid)
            log.info("  remote client detected (pid %s not in /proc)", nvim_pid)

    def _seed_agent_type(self, nvim_pid: int, buf: int, inst: dict) -> None:
        """Seed the sticky backend identity from a registration payload.

        Backend identity ("claude" | "opencode") now travels with the
        orchestrator's sync/added registration, not only the ephemeral activity
        channel. Seeding here makes a freshly-restarted bridge (it dies with the
        shell, wiping _agent_types) type every agent correctly from the first
        snapshot — without this, all agents default to "claude" until their next
        activity event fires.

        Only seeds when the payload carries a non-empty agent_type, matching the
        sticky semantics of the activity path: an older orchestrator that doesn't
        report the field leaves any existing/activity-derived type untouched.
        """
        agent_type = inst.get("agent_type", "")
        if agent_type:
            self._agent_types[f"{nvim_pid}_{buf}"] = agent_type

    def _snapshot_line(self) -> str:
        """Build the consolidated-state JSON line (without writing it anywhere)."""
        agents = []
        projects = set()

        for nvim_pid, instances in self._clients.items():
            for buf, inst in instances.items():
                project = inst.get("project", "unknown")
                projects.add(project)
                agent_id = f"{nvim_pid}_{buf}"
                activity = self._activities.get(agent_id, {})
                agents.append({
                    "id": agent_id,
                    "nvim_pid": nvim_pid,
                    "buf": buf,
                    "project": project,
                    "title": inst.get("title", ""),
                    "color_idx": inst.get("color_idx", 0),
                    "dangerous": inst.get("dangerous", False),
                    "active": inst.get("active", False),
                    "spawn_type": inst.get("spawn_type", "fresh"),
                    "spawned_at": inst.get("spawned_at", 0),
                    "terminal_pid": self._terminal_pids.get(nvim_pid, 0),
                    # Real RPC socket from hello (v:servername); "" → consumer
                    # falls back to the pid-derived default path.
                    "nvim_socket": self._nvim_sockets.get(nvim_pid, ""),
                    "remote": nvim_pid in self._remote_clients,
                    # Backend identity drives the dashboard accent color. Read
                    # from the sticky _agent_types map (NOT activity) so it
                    # survives idle, when the activity entry is gone. "" →
                    # treated as Claude downstream (backward-compatible).
                    "agent_type": self._agent_types.get(agent_id, ""),
                    "activity_state": activity.get("state", ""),
                    "activity_tool": activity.get("tool", ""),
                    "in_plan_mode": activity.get("in_plan_mode", False),
                })

        # Sort: by project, then by spawn time within project
        agents.sort(key=lambda a: (a["project"], a["spawned_at"]))

        payload = {
            "agents": agents,
            "projects": sorted(projects),
        }
        line = json.dumps(payload)
        log.debug("_snapshot: %d agents, %d projects, %d clients, %d subscriber(s) — %d bytes",
                   len(agents), len(projects), len(self._clients),
                   len(self._subscribers), len(line))
        return line

    def _emit(self) -> None:
        """Write consolidated state to stdout (QML SplitParser) + socket subscribers."""
        line = self._snapshot_line()
        sys.stdout.write(line + "\n")
        sys.stdout.flush()
        if self._subscribers:
            data = (line + "\n").encode()
            for w in list(self._subscribers):
                if w.is_closing():
                    self._subscribers.discard(w)
                    continue
                try:
                    w.write(data)
                except Exception as e:  # noqa: BLE001 — any write failure means dead peer
                    log.warning("_emit: dropping dead subscriber (%s)", e)
                    self._subscribers.discard(w)

    def add_subscriber(self, writer: asyncio.StreamWriter) -> None:
        """Register a snapshot subscriber and push the current state immediately.

        The initial snapshot goes only to the new writer (not stdout), so a
        late-joining consumer (the IDE) gets current state without producing
        a redundant stdout line for the shell.
        """
        self._subscribers.add(writer)
        log.info("subscribe: %d subscriber(s) registered", len(self._subscribers))
        try:
            writer.write((self._snapshot_line() + "\n").encode())
        except Exception as e:  # noqa: BLE001
            log.warning("add_subscriber: initial snapshot failed (%s)", e)
            self._subscribers.discard(writer)

    def remove_subscriber(self, writer: asyncio.StreamWriter) -> None:
        """Drop a subscriber (idempotent; called from handle_client cleanup)."""
        if writer in self._subscribers:
            self._subscribers.discard(writer)
            log.info("unsubscribe: %d subscriber(s) remain", len(self._subscribers))

    def _schedule_emit(self) -> None:
        """Coalesced emit: leading edge fires immediately, then 50ms cooldown.

        During the cooldown, additional calls just set _emit_dirty. When the
        cooldown expires, if dirty, one final trailing-edge emit fires.
        Result: N events in a 50ms burst → exactly 2 stdout emissions.
        """
        if self._emit_handle is None:
            # Leading edge — emit immediately + start cooldown
            self._emit()
            self._emit_dirty = False
            loop = asyncio.get_running_loop()
            self._emit_handle = loop.call_later(0.05, self._end_coalesce)
        else:
            # During cooldown — mark dirty for trailing edge
            self._emit_dirty = True

    def _end_coalesce(self) -> None:
        """Trailing edge of coalescing window: emit once if dirty, then clear."""
        self._emit_handle = None
        if self._emit_dirty:
            self._emit_dirty = False
            self._emit()

    def handle_message(self, msg: dict) -> None:
        """Process a single JSON message from an orchestrator or hook client."""
        msg_type = msg.get("type")

        # Activity messages come from hook scripts (ephemeral connections)
        # and use agent_id instead of nvim_pid — handle before validation.
        # Note: states like "needs_permission" are cleared implicitly when
        # any subsequent event overwrites the entry (e.g., PreToolUse → "working").
        if msg_type == "activity":
            agent_id = msg.get("agent_id", "")
            if not agent_id:
                return
            state = msg.get("state", "")
            tool = msg.get("tool", "")
            plan = msg.get("in_plan_mode", False)
            # Sticky backend identity: only overwrite when the reporter actually
            # supplies it, so a stray message without the field never wipes a
            # known type. Absent for legacy/unknown reporters → "" → the QML
            # dashboard treats it as Claude (backward-compatible default).
            agent_type = msg.get("agent_type", "")
            if agent_type:
                self._agent_types[agent_id] = agent_type
            hook_event = msg.get("hook_event", "")
            event_ts_ns = int(msg.get("event_ts_ns", 0) or 0)

            prev_entry = self._activities.get(agent_id)
            prev_state = prev_entry.get("state", "") if prev_entry else ""
            prev_event_ts_ns = int(prev_entry.get("event_ts_ns", 0) or 0) if prev_entry else 0

            # Out-of-order detection: an async hook invocation can lose its
            # race over the Unix socket and arrive AFTER a logically later
            # event. We log the anomaly but DO NOT drop the message, since
            # this code path is new and we don't yet have data on whether
            # ignoring older events is always safe (e.g., a "Stop" arriving
            # late might still be the correct final state). The history
            # records the ooo flag so we can revisit this decision with data.
            ooo = bool(event_ts_ns and prev_event_ts_ns and event_ts_ns < prev_event_ts_ns)
            if ooo:
                lag_ms = (prev_event_ts_ns - event_ts_ns) / 1_000_000
                log.warning(
                    "activity OUT-OF-ORDER | %s event=%s state=%s arrived %dms after newer event (prev_state=%s)",
                    agent_id, hook_event or "?", state, int(lag_ms), prev_state or "-",
                )

            # SubagentStart/Stop pairing — Claude Code's recap is implemented
            # as a background subagent that fires SubagentStop AFTER the
            # parent agent's Stop has already cleared the slot. By tracking
            # a per-parent-agent depth counter, we can deterministically
            # classify any unpaired SubagentStop as a recap echo and drop
            # it. SubagentStart paired with a real Task() call still works
            # exactly as before because the counter increments first.
            if hook_event == "SubagentStart":
                self._subagent_depth[agent_id] = self._subagent_depth.get(agent_id, 0) + 1
                log.debug("subagent | %s start (depth now %d)",
                          agent_id, self._subagent_depth[agent_id])
            elif hook_event == "SubagentStop":
                depth = self._subagent_depth.get(agent_id, 0)
                if depth > 0:
                    self._subagent_depth[agent_id] = depth - 1
                    log.debug("subagent | %s stop (depth now %d)",
                              agent_id, self._subagent_depth[agent_id])
                else:
                    # Unpaired SubagentStop — this is the recap signature.
                    # Record it in history for postmortem visibility but do
                    # NOT touch _activities; let the agent stay idle.
                    log.info("RECAP DETECTED | %s SubagentStop without preceding SubagentStart — dropping (was state=%s)",
                             agent_id, prev_state or "idle")
                    self._append_to_history(agent_id, "SubagentStop", "(dropped: recap)",
                                             tool, event_ts_ns, ooo)
                    return  # Skip _activities update + emit entirely

            # SubagentStart/Stop depth tracking is complete. Both SubagentStart
            # (depth++) and SubagentStop with depth > 0 (depth--) fall through
            # here to apply the normal state update in _activities.
            if state in ("offline", "idle"):
                self._activities.pop(agent_id, None)
                self._warned_stuck.discard(agent_id)
                # Parent Stop clears any outstanding subagent counter — a
                # SubagentStop arriving after this point is by definition
                # orphan (the recap pattern). Without this clear, a Task
                # subagent that legitimately ran during the parent turn
                # would consume a counter slot meant for a future turn.
                self._subagent_depth.pop(agent_id, None)
            else:
                self._activities[agent_id] = {
                    "state": state,
                    "tool": tool,
                    "ts": time.monotonic(),
                    "event_ts_ns": event_ts_ns,
                    # Hook reads permission_mode on every event, so in_plan_mode
                    # is always current — no accumulation needed.
                    "in_plan_mode": plan,
                    "hook_event": hook_event,
                }
                # Any genuine new state clears the prior stuck warning so the
                # watchdog can re-warn next time it gets stuck.
                if prev_state != state:
                    self._warned_stuck.discard(agent_id)

            # Record into per-agent history ring buffer (always, even for
            # idle/offline, so postmortems can see the final transition).
            self._append_to_history(agent_id, hook_event, state, tool, event_ts_ns, ooo)

            # History is always recorded above (even no-ops). Log only state transitions
            # to avoid noise from repeated same-state events (e.g., multiple PreToolUse).
            if prev_state != state:
                log.info("activity | %s %s→%s event=%s tool=%s plan=%s",
                         agent_id, prev_state or "-", state, hook_event or "?", tool, plan)
            self._schedule_emit()
            return

        # Notification messages are pass-through: enrich with project/terminal_pid
        # and forward to stdout. No agent state change (no _emit call).
        if msg_type == "notification":
            agent_id = msg.get("agent_id", "")
            if not agent_id:
                return

            nvim_pid_str, _, buf_str = agent_id.partition("_")
            nvim_pid = int(nvim_pid_str) if nvim_pid_str.isdigit() else 0
            buf = int(buf_str) if buf_str.isdigit() else -1

            project = "unknown"
            terminal_pid = 0
            if nvim_pid in self._clients and buf in self._clients[nvim_pid]:
                project = self._clients[nvim_pid][buf].get("project", "unknown")
            terminal_pid = self._terminal_pids.get(nvim_pid, 0)

            # Stamp the backend identity onto the notification so the QML layer
            # can pick the matching icon (Claude sparkle vs OpenCode grid). The
            # plugin's notification payload doesn't carry agent_type, so seed it
            # from the bridge's sticky _agent_types map — the authoritative source
            # that survives idle (it's what agent snapshots also report). Absent →
            # "" which the QML treats as Claude (backward-compatible).
            agent_type = self._agent_types.get(agent_id, "")
            enriched = {**msg, "project": project, "terminal_pid": terminal_pid,
                        "agent_type": agent_type}
            line = json.dumps(enriched)
            log.debug("handle_message: notification pass-through agent_id=%s project=%s terminal_pid=%d type=%s",
                       agent_id, project, terminal_pid, agent_type or "claude")
            sys.stdout.write(line + "\n")
            sys.stdout.flush()
            return

        nvim_pid = msg.get("nvim_pid")

        if not msg_type or nvim_pid is None:
            log.warning("handle_message: missing type or nvim_pid in %s", msg)
            return

        log.info("handle_message: type=%s nvim_pid=%s", msg_type, nvim_pid)

        # Desync recovery: if a state-mutation message arrives for a pid we
        # have no client entry for, the orchestrator is alive but we lost
        # its registration (most commonly: a parallel-connection race during
        # bridge restart wiped the state). Trigger a one-shot reconnect RPC
        # (throttled). Don't drop the message — fall through to the normal
        # handler which will log its own "unknown" warning. The next hello+
        # sync from the resolicit will re-establish the client and future
        # messages will work.
        if msg_type in self._DESYNC_TYPES and nvim_pid not in self._clients:
            self.maybe_resolicit(nvim_pid)

        if msg_type == "hello":
            self._clients.setdefault(nvim_pid, {})
            # Detect remote clients (PID doesn't exist in local /proc — tunneled via SSH)
            self._ensure_remote_detected(nvim_pid)
            # An explicitly DECLARED host window PID (Symmetria IDE's bridge
            # client sends its own pid — the Hyprland window pid) always
            # beats the inferred /proc walk: an IDE launched from a dev
            # terminal has a real terminal ancestor that the walk would
            # wrongly resolve to, and the environ fallback can't see the
            # IDE's own putenv (post-exec env changes don't reach
            # /proc/pid/environ). Overwrite on every hello, like the socket.
            declared_host = msg.get("host_window_pid") or 0
            if declared_host:
                self._terminal_pids[nvim_pid] = int(declared_host)
            # Resolve terminal PID on first contact (stable for session lifetime)
            elif nvim_pid not in self._terminal_pids:
                self._terminal_pids[nvim_pid] = self._resolve_terminal_pid(nvim_pid)
            # Record the real RPC socket (v:servername). Overwrite on every
            # hello — a reconnect after :restart could carry a new path.
            sock = msg.get("nvim_socket") or ""
            if sock:
                self._nvim_sockets[nvim_pid] = sock
            log.debug("  hello: registered client %s (terminal_pid=%d, socket=%s, remote=%s, total clients: %d)",
                       nvim_pid, self._terminal_pids.get(nvim_pid, 0), sock,
                       nvim_pid in self._remote_clients, len(self._clients))
            # Don't emit: hello registers the client slot but carries no agent data.
            # The subsequent "sync" message will emit with the full initial state.

        elif msg_type == "sync":
            instances = {}
            for inst in msg.get("instances", []):
                buf = inst.get("buf")
                if buf is not None:
                    instances[buf] = inst
                    self._seed_agent_type(nvim_pid, buf, inst)
            self._clients[nvim_pid] = instances
            # Detect remote on sync too (covers reconnect after bridge restart)
            self._ensure_remote_detected(nvim_pid)
            # Re-resolve terminal PID on sync (covers reconnect after bridge restart)
            if nvim_pid not in self._terminal_pids:
                self._terminal_pids[nvim_pid] = self._resolve_terminal_pid(nvim_pid)
            log.debug("  sync: %d instances from pid %s (terminal_pid=%d)",
                       len(instances), nvim_pid, self._terminal_pids.get(nvim_pid, 0))
            self._schedule_emit()

        elif msg_type == "added":
            inst = msg.get("instance", {})
            buf = inst.get("buf")
            if buf is not None:
                self._clients.setdefault(nvim_pid, {})[buf] = inst
                self._seed_agent_type(nvim_pid, buf, inst)
                log.debug("  added: buf=%s active=%s from pid %s", buf, inst.get("active"), nvim_pid)
                self._schedule_emit()
            else:
                log.warning("  added: missing buf from pid %s", nvim_pid)

        elif msg_type == "removed":
            buf = msg.get("buf")
            if nvim_pid in self._clients and buf in self._clients[nvim_pid]:
                del self._clients[nvim_pid][buf]
                aid = f"{nvim_pid}_{buf}"
                self._clear_agent_state(aid)
                log.debug("  removed: buf=%s from pid %s", buf, nvim_pid)
                self._schedule_emit()
            else:
                log.warning("  removed: unknown buf=%s for pid=%s (known: %s)",
                            buf, nvim_pid, list(self._clients.get(nvim_pid, {}).keys()))

        elif msg_type == "updated":
            buf = msg.get("buf")
            if nvim_pid in self._clients and buf in self._clients[nvim_pid]:
                # Merge updated fields
                for key in ("title", "color_idx", "dangerous", "spawn_type"):
                    if key in msg:
                        self._clients[nvim_pid][buf][key] = msg[key]
                log.debug("  updated: buf=%s from pid %s", buf, nvim_pid)
                self._schedule_emit()
            else:
                log.warning("  updated: unknown buf=%s for pid=%s (known: %s)",
                            buf, nvim_pid, list(self._clients.get(nvim_pid, {}).keys()))

        elif msg_type == "liveness":
            dead_bufs = msg.get("dead_bufs", [])
            quiet_bufs = msg.get("quiet_bufs", [])
            cleared_any = False
            for buf in dead_bufs:
                agent_id = f"{nvim_pid}_{buf}"
                if agent_id in self._activities:
                    log.info("  liveness: clearing DEAD agent %s (was %s)",
                             agent_id, self._activities[agent_id].get("state"))
                    self._clear_agent_state(agent_id)
                    cleared_any = True
            for buf in quiet_bufs:
                agent_id = f"{nvim_pid}_{buf}"
                if agent_id in self._activities:
                    log.info("  liveness: clearing QUIET agent %s (was %s, terminal silent 60s+)",
                             agent_id, self._activities[agent_id].get("state"))
                    self._clear_agent_state(agent_id)
                    cleared_any = True
            if cleared_any:
                self._schedule_emit()

        elif msg_type == "focus":
            buf = msg.get("buf")
            if nvim_pid in self._clients:
                known_bufs = self._clients[nvim_pid]
                if buf not in known_bufs:
                    log.warning("  focus: buf=%s not in known instances for pid=%s (known: %s) — ignoring",
                                buf, nvim_pid, list(known_bufs.keys()))
                    return  # Don't unfocus all agents for an unknown buf
                for b, inst in known_bufs.items():
                    inst["active"] = (b == buf)
                log.debug("  focus: buf=%s from pid %s", buf, nvim_pid)
                self._schedule_emit()
            else:
                log.warning("  focus: unknown pid=%s (not registered)", nvim_pid)

        elif msg_type == "goodbye":
            if nvim_pid in self._clients:
                # Clean up activities for all agents belonging to this nvim instance
                for buf in self._clients[nvim_pid]:
                    self._clear_agent_state(f"{nvim_pid}_{buf}")
                del self._clients[nvim_pid]
                self._terminal_pids.pop(nvim_pid, None)
                self._nvim_sockets.pop(nvim_pid, None)
                self._remote_clients.discard(nvim_pid)
                # Clear per-pid counters so a reconnect from this pid starts fresh.
                self._conn_count.pop(nvim_pid, None)
                self._last_resolicit.pop(nvim_pid, None)
                log.debug("  goodbye: removed client %s (remaining: %d)", nvim_pid, len(self._clients))
                self._schedule_emit()
        else:
            log.warning("  unknown message type: %s", msg_type)

    def remove_client(self, nvim_pid: int) -> None:
        """Remove all state for a disconnected client."""
        if nvim_pid in self._clients:
            count = len(self._clients[nvim_pid])
            log.info("remove_client: dropping pid=%s (%d instances), remaining clients: %d",
                     nvim_pid, count, len(self._clients) - 1)
            # Clean up activities for all agents belonging to this nvim instance
            for buf in self._clients[nvim_pid]:
                self._clear_agent_state(f"{nvim_pid}_{buf}")
            del self._clients[nvim_pid]
            self._terminal_pids.pop(nvim_pid, None)
            self._nvim_sockets.pop(nvim_pid, None)
            self._remote_clients.discard(nvim_pid)
            # Clear the per-pid connection counter and resolicit throttle so
            # a reconnect from this same pid starts fresh. Without this, a pid
            # that reconnects within 10s of a clean disconnect would not trigger
            # desync recovery (stale _last_resolicit blocks the RPC).
            self._conn_count.pop(nvim_pid, None)
            self._last_resolicit.pop(nvim_pid, None)
            self._schedule_emit()
        else:
            log.debug("remove_client: pid=%s not in clients (already removed?)", nvim_pid)

    def reap_stale_activities(self) -> None:
        """Clear activity entries that haven't been updated within the staleness timeout.

        Only reaps activities for agents NOT registered in _clients (orphaned
        entries from crashed sessions or hook race conditions). Registered
        agents are protected — Claude Code can legitimately go silent for
        minutes during long thinking/planning phases. Use manual assertion
        via the orchestrator keybind to force-check agent liveness.
        """
        now = time.monotonic()
        stale_ids = []
        for aid, act in self._activities.items():
            if act.get("state") in ("idle", ""):
                continue
            if (now - act.get("ts", now)) <= ACTIVITY_STALENESS_TIMEOUT:
                continue

            # Check if agent is still registered (orchestrator connection alive)
            nvim_pid_str, _, buf_str = aid.partition("_")
            try:
                nvim_pid = int(nvim_pid_str)
                buf = int(buf_str)
            except ValueError:
                stale_ids.append(aid)  # Malformed ID — reap
                continue

            if nvim_pid in self._clients and buf in self._clients[nvim_pid]:
                continue  # Session alive — don't reap

            stale_ids.append(aid)

        if stale_ids:
            for aid in stale_ids:
                log.info("reap_stale_activities: %s orphaned+stale (was %s), clearing",
                         aid, self._activities[aid].get("state"))
                self._clear_agent_state(aid)
            self._schedule_emit()

    def check_stuck_working(self) -> None:
        """Log a warning for any agent stuck in 'working' beyond the threshold.

        Purely observational — does NOT clear the state. Real recovery is
        the orchestrator's terminal-silence path (quiet_bufs liveness). The
        warning carries the per-agent activity history so we can correlate
        the stuck event with the hook sequence that led to it.
        """
        now = time.monotonic()
        # asyncio single-thread: iteration is safe — no concurrent modification
        # can occur within a single coroutine turn (the reaper awaits between calls).
        for aid, act in self._activities.items():
            if act.get("state") != "working":
                continue
            stuck_for = now - act.get("ts", now)
            if stuck_for < STUCK_WORKING_WARN_SECONDS:
                continue
            if aid in self._warned_stuck:
                continue
            self._warned_stuck.add(aid)
            history = list(self._activity_history.get(aid, []))
            tail = history[-5:] if history else []
            tail_str = " | ".join(
                f"{h.get('state')}({h.get('hook_event','?')})"
                for h in tail
            )
            log.warning(
                "STUCK WORKING | %s in 'working' for %ds (last 5: %s)",
                aid, int(stuck_for), tail_str or "(no history)",
            )

    def write_diagnostic_dump(self) -> None:
        """Serialize full bridge state to DIAGNOSTIC_DUMP_PATH for postmortem.

        Triggered by SIGUSR1. Captures everything an investigator might
        want: all clients, all activity entries, complete per-agent history
        ring buffers, terminal/remote info, and timing context. Writes
        atomically (.tmp + rename) so a reader can't observe a half-written
        file.
        """
        try:
            now_mono = time.monotonic()
            dump = {
                "ts_iso": datetime.now().isoformat(timespec="milliseconds"),
                "ts_mono": now_mono,
                "pid": os.getpid(),
                "clients": {
                    str(pid): {
                        "instances": list(insts.values()),
                        "terminal_pid": self._terminal_pids.get(pid, 0),
                        "remote": pid in self._remote_clients,
                    }
                    for pid, insts in self._clients.items()
                },
                "activities": {
                    aid: {
                        **act,
                        "stuck_for_seconds": now_mono - act.get("ts", now_mono),
                    }
                    for aid, act in self._activities.items()
                },
                "history": {
                    aid: list(hist) for aid, hist in self._activity_history.items()
                },
                "warned_stuck": sorted(self._warned_stuck),
                "agent_types": dict(self._agent_types),
                "subagent_depth": dict(self._subagent_depth),
                "conn_count": dict(self._conn_count),
                "subscriber_count": len(self._subscribers),
                "last_resolicit": {str(k): v for k, v in self._last_resolicit.items()},
            }
            DIAGNOSTIC_DUMP_PATH.parent.mkdir(parents=True, exist_ok=True)
            tmp = DIAGNOSTIC_DUMP_PATH.with_suffix(".tmp")
            tmp.write_text(json.dumps(dump, indent=2, default=str))
            tmp.replace(DIAGNOSTIC_DUMP_PATH)
            log.info("DIAGNOSTIC DUMP written → %s (%d agents, %d activities, %d histories)",
                     DIAGNOSTIC_DUMP_PATH,
                     sum(len(c) for c in self._clients.values()),
                     len(self._activities),
                     len(self._activity_history))
        except Exception as exc:  # noqa: BLE001
            log.error("write_diagnostic_dump: failed: %s", exc)

    def _append_to_history(self, agent_id: str, hook_event: str, state: str,
                           tool: str, event_ts_ns: int, ooo: bool) -> None:
        """Append a transition record to the per-agent activity history ring buffer.

        Called for every activity update (including drops) so postmortems have
        a complete transition log. The ring buffer caps at ACTIVITY_HISTORY_DEPTH.
        """
        history = self._activity_history.setdefault(
            agent_id, deque(maxlen=ACTIVITY_HISTORY_DEPTH)
        )
        history.append({
            "ts_iso": datetime.now().isoformat(timespec="milliseconds"),
            "ts_mono": time.monotonic(),
            "event_ts_ns": event_ts_ns,
            "hook_event": hook_event,
            "state": state,
            "tool": tool,
            "ooo": ooo,
        })

    def _clear_agent_state(self, aid: str) -> None:
        """Remove all per-agent state for a given agent_id.

        Called from removed/goodbye/remove_client and reap_stale_activities
        to ensure all four per-agent dicts stay consistent. Centralises the
        teardown so new dicts only need to be added here.
        """
        self._activities.pop(aid, None)
        self._agent_types.pop(aid, None)
        self._activity_history.pop(aid, None)
        self._subagent_depth.pop(aid, None)
        self._warned_stuck.discard(aid)

    def maybe_resolicit(self, nvim_pid: int) -> None:
        """Trigger a reconnect-RPC to a desync'd orchestrator, throttled.

        Called from handle_message when a state-mutation message arrives for
        an nvim_pid we have no client entry for. The orchestrator is alive
        (it's sending us messages) but has not registered (no hello/sync)
        — so we ask it to re-send its full state. Throttled to once per
        10 seconds per pid; without throttling, an unregistered orchestrator
        sending updates every ~1s would trigger one RPC per message.

        Silently no-ops if the nvim socket no longer exists (the process
        died — desync is moot).
        """
        now = time.monotonic()
        if now - self._last_resolicit.get(nvim_pid, 0) < 10:
            return
        socket_path = f"/run/user/{os.getuid()}/nvim.{nvim_pid}.0"
        if not Path(socket_path).exists():
            log.debug("maybe_resolicit: pid=%s socket missing, skipping", nvim_pid)
            return
        self._last_resolicit[nvim_pid] = now
        log.warning(
            "DESYNC | pid=%s sent message without prior hello/sync — soliciting reconnect",
            nvim_pid,
        )
        asyncio.create_task(solicit_neovim_instance(socket_path))


bridge = AgentBridge()


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    """Handle a single orchestrator connection.

    The orchestrator can briefly hold multiple parallel connections from the
    same nvim_pid — this happens routinely during bridge restart when the
    bridge's solicit-RPC and the orchestrator's own auto-reconnect both fire
    within milliseconds of each other. Per-pid connection counting (managed
    via bridge._conn_count) ensures remove_client only fires when the LAST
    connection closes; otherwise a 1ms-overlapping race destroys client
    state for the entire bridge lifetime.
    """
    peername = writer.get_extra_info("peername")
    log.info("CLIENT CONNECTED: peername=%s", peername)
    nvim_pid = None
    counted = False  # True after we've incremented _conn_count for this connection
    try:
        async for line in reader:
            text = line.decode("utf-8", errors="replace").strip()
            if not text:
                continue
            try:
                msg = json.loads(text)
            except json.JSONDecodeError:
                log.warning("CLIENT: bad JSON from pid=%s: %s", nvim_pid, text[:100])
                continue

            # Subscribe: register this connection for snapshot fan-out and send
            # the current consolidated state immediately so a late-joining
            # consumer (the Symmetria IDE) doesn't wait for the next change.
            # Handled here (not in handle_message) because only handle_client
            # owns the writer. A subscribe-only connection never sets nvim_pid,
            # so it takes the ephemeral-conn path below — no _conn_count entry,
            # no remove_client on disconnect. A publisher connection (hello
            # first, then subscribe — the IDE's single-connection mode) keeps
            # its normal client lifecycle; the subscription is orthogonal.
            if msg.get("type") == "subscribe":
                bridge.add_subscriber(writer)
                continue

            # Track nvim_pid from first message AND increment the per-pid
            # connection counter. A given physical connection contributes
            # exactly one count regardless of how many messages it sends.
            if nvim_pid is None:
                nvim_pid = msg.get("nvim_pid")
                if nvim_pid is not None:
                    bridge._conn_count[nvim_pid] = bridge._conn_count.get(nvim_pid, 0) + 1
                    counted = True
                    log.info("CLIENT identified: nvim_pid=%s (open conns now %d)",
                             nvim_pid, bridge._conn_count[nvim_pid])
                else:
                    log.info("CLIENT identified: nvim_pid=None (ephemeral hook conn)")

            bridge.handle_message(msg)
        log.info("CLIENT EOF: nvim_pid=%s (reader exhausted)", nvim_pid)
    except asyncio.CancelledError:
        log.info("CLIENT CANCELLED: nvim_pid=%s", nvim_pid)
    except Exception as e:
        log.error("CLIENT ERROR: nvim_pid=%s, error=%s", nvim_pid, e)
    finally:
        log.info("CLIENT CLEANUP: nvim_pid=%s, closing writer", nvim_pid)
        bridge.remove_subscriber(writer)  # idempotent — no-op for non-subscribers
        writer.close()
        # Only call remove_client when the LAST connection from this pid
        # closes. The previous behavior (unconditional remove_client on
        # every connection close) destroyed state for any sibling
        # connection still alive — the .dotfiles-agent-disappears bug.
        if nvim_pid is not None and counted:
            remaining = bridge._conn_count.get(nvim_pid, 1) - 1
            if remaining <= 0:
                bridge._conn_count.pop(nvim_pid, None)
                log.info("CLIENT last-conn-closed | pid=%s, removing client state", nvim_pid)
                bridge.remove_client(nvim_pid)
            else:
                bridge._conn_count[nvim_pid] = remaining
                log.debug("CLIENT conn-closed | pid=%s, %d sibling(s) still open — keeping state",
                          nvim_pid, remaining)


async def solicit_neovim_instance(socket_path: str) -> bool:
    """Trigger reconnect() on a single Neovim instance via RPC.

    Uses nvim --remote-expr to call bridge.reconnect() in the target Neovim.
    Returns True if the call succeeded, False otherwise.
    """
    cmd = [
        "nvim", "--server", socket_path, "--remote-expr",
        'luaeval("require(\'orchestrator.bridge\').reconnect()")',
    ]
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=2.0)
        result = stdout.decode().strip() if stdout else ""
        if proc.returncode == 0:
            log.info("solicit %s: ok (result=%s)", socket_path, result)
            return True
        else:
            log.debug("solicit %s: failed (rc=%d, stderr=%s)",
                      socket_path, proc.returncode, stderr.decode().strip()[:100] if stderr else "")
            return False
    except asyncio.TimeoutError:
        log.debug("solicit %s: timed out (2s)", socket_path)
        try:
            proc.kill()  # type: ignore[possibly-undefined]  # only wait_for raises TimeoutError, after proc is assigned
            await proc.wait()  # type: ignore[possibly-undefined]
        except ProcessLookupError:
            pass
        return False
    except OSError as e:
        log.debug("solicit %s: OSError %s", socket_path, e)
        return False


async def solicit_neovim_instances() -> None:
    """Discover running Neovim instances and trigger reconnection.

    Scans /run/user/$UID/nvim.*.0 for Neovim server sockets and issues
    parallel RPC calls to each, triggering orchestrator.bridge.reconnect().
    """
    socket_dir = Path(f"/run/user/{os.getuid()}")
    sockets = sorted(socket_dir.glob("nvim.*.0"))

    if not sockets:
        log.info("solicit: no Neovim sockets found in %s", socket_dir)
        return

    log.info("solicit: found %d Neovim socket(s), triggering reconnect...", len(sockets))
    results = await asyncio.gather(
        *(solicit_neovim_instance(str(s)) for s in sockets),
        return_exceptions=True,
    )

    succeeded = sum(1 for r in results if r is True)
    log.info("solicit: %d/%d Neovim instances reconnected", succeeded, len(sockets))


def cleanup_socket():
    """Remove socket file on exit — only if we created it.

    Prevents a stale bridge.py process from deleting a newer process's socket
    when its atexit handler runs after the new process has already bound.
    """
    try:
        if _our_socket_inode is not None and SOCKET_PATH.stat().st_ino == _our_socket_inode:
            SOCKET_PATH.unlink(missing_ok=True)
    except OSError:
        pass


def _signal_stale_bridges() -> None:
    """Send SIGTERM to any other agent-bridge.py processes from previous sessions.

    Uses SIGTERM only (no SIGKILL follow-up) to avoid fratricide crash loops
    when old and new shell sessions overlap during restart. The old bridge will
    either shut down gracefully via its SIGTERM handler, or become orphaned
    when we take over the socket path (harmless — it just sits idle until its
    parent qs process exits).

    Previous approach used SIGTERM + 0.5s sleep + SIGKILL, which caused a
    crash loop: both sessions' bridges would kill each other repeatedly,
    accumulating exponential backoff delays (16+ crashes, 30s+ restarts).
    """
    my_pid = os.getpid()
    try:
        result = subprocess.run(
            ["pgrep", "-u", str(os.getuid()), "-f", "agent-bridge\\.py"],
            capture_output=True, text=True, timeout=2,
        )
        for line in result.stdout.strip().splitlines():
            pid = int(line.strip())
            if pid != my_pid:
                log.info("signaling stale bridge.py pid=%d (SIGTERM)", pid)
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass  # Already exited
    except Exception as e:
        log.debug("_signal_stale_bridges: %s", e)


async def main():
    global _our_socket_inode

    # Signal orphaned bridge.py processes from previous sessions (SIGTERM only —
    # no SIGKILL to avoid fratricide crash loops during shell restart)
    _signal_stale_bridges()

    # Clean up stale socket
    log.info("STARTING: cleaning stale socket at %s", SOCKET_PATH)
    SOCKET_PATH.unlink(missing_ok=True)
    atexit.register(cleanup_socket)

    server = await asyncio.start_unix_server(handle_client, path=str(SOCKET_PATH))
    # Ensure socket is accessible
    SOCKET_PATH.chmod(0o600)

    # Record our socket's inode for ownership-safe cleanup
    _our_socket_inode = SOCKET_PATH.stat().st_ino
    log.info("LISTENING on %s (pid=%d, inode=%d)", SOCKET_PATH, os.getpid(), _our_socket_inode)

    # Actively solicit running Neovim instances to reconnect
    asyncio.create_task(solicit_neovim_instances())

    # Periodic staleness reaper — clears orphaned activity entries (no live
    # orchestrator connection). Registered agents are never reaped by timeout.
    # Also runs the stuck-working watchdog (purely observational logging).
    async def activity_reaper():
        while True:
            await asyncio.sleep(5)  # Check every 5 seconds
            try:
                bridge.reap_stale_activities()
                bridge.check_stuck_working()
            except Exception as exc:  # noqa: BLE001
                log.error("activity_reaper: unexpected error: %s", exc)
    asyncio.create_task(activity_reaper())

    # Handle signals for clean shutdown
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, lambda: loop.create_task(shutdown(server)))

    # SIGUSR1 → write a full diagnostic dump to disk. Use this from a stuck-
    # state symptom: `pkill -USR1 -f agent-bridge.py` then read the file at
    # ~/.local/state/symmetria/agent-bridge-diagnostic.json.
    loop.add_signal_handler(signal.SIGUSR1, bridge.write_diagnostic_dump)

    async with server:
        await server.serve_forever()


_shutting_down = False


async def shutdown(server):
    """Graceful shutdown (guarded against double-invocation from SIGTERM+SIGINT)."""
    global _shutting_down
    if _shutting_down:
        return
    _shutting_down = True

    log.info("SHUTDOWN: closing server...")
    server.close()
    await server.wait_closed()
    tasks = [t for t in asyncio.all_tasks() if t is not asyncio.current_task()]
    log.info("SHUTDOWN: cancelling %d tasks", len(tasks))
    for task in tasks:
        task.cancel()
    await asyncio.gather(*tasks, return_exceptions=True)
    log.info("SHUTDOWN: all tasks finished")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit):
        cleanup_socket()
