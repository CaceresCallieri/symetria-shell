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
import logging
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

SOCKET_PATH = Path(f"/run/user/{os.getuid()}/symmetria-agents.sock")

# Seconds before an orphaned activity entry (no live orchestrator connection)
# is reaped. Registered agents are never reaped by timeout.
ACTIVITY_STALENESS_TIMEOUT = 15

# Inode of the socket we created — used to avoid deleting a newer process's socket
_our_socket_inode: int | None = None

# Debug logging to stderr (stdout is reserved for QML SplitParser data).
# Default WARNING in production; override with AGENT_BRIDGE_LOG_LEVEL=DEBUG.
_log_level = os.environ.get("AGENT_BRIDGE_LOG_LEVEL", "WARNING").upper()
logging.basicConfig(
    stream=sys.stderr,
    level=getattr(logging, _log_level, logging.WARNING),
    format="[bridge.py %(levelname)s] %(message)s",
)
log = logging.getLogger("agent-bridge")


class AgentBridge:
    """Aggregates agent state from all connected orchestrator instances."""

    # Terminal emulator process names to match when walking /proc upward.
    TERMINAL_NAMES = frozenset({
        "ghostty", "kitty", "alacritty", "foot", "wezterm-gui",
        "konsole", "gnome-terminal", "xfce4-terminal", "xterm",
        "terminator", "tilix", "sakura", "st", "urxvt",
    })

    def __init__(self):
        # {nvim_pid: {buf: instance_data, ...}}
        self._clients: dict[int, dict[int, dict]] = {}
        # {nvim_pid: terminal_pid} — cached terminal PID per Neovim instance
        self._terminal_pids: dict[int, int] = {}
        # {agent_id: {"state": str, "tool": str, "ts": float, "in_plan_mode": bool}} — activity state from hook scripts
        self._activities: dict[str, dict] = {}

        # Emit coalescing: leading-edge + trailing-edge with 50ms cooldown.
        # Prevents stdout floods during startup reconnect bursts (30+ events → 2 emissions).
        self._emit_handle: asyncio.TimerHandle | None = None
        self._emit_dirty: bool = False

    @staticmethod
    def _resolve_terminal_pid(nvim_pid: int) -> int:
        """Walk /proc upward from nvim_pid to find the terminal emulator PID.

        Reads /proc/{pid}/stat for each ancestor: field 2 is the comm name
        (in parens), field 4 is the parent PID.  Returns 0 if no terminal
        emulator is found before reaching PID 1.
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
        log.debug("_resolve_terminal_pid: %d → no terminal found", nvim_pid)
        return 0

    def _emit(self) -> None:
        """Write consolidated state to stdout (consumed by QML SplitParser)."""
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
                    "terminal_pid": self._terminal_pids.get(nvim_pid, 0),
                    "activity_state": activity.get("state", ""),
                    "activity_tool": activity.get("tool", ""),
                    "in_plan_mode": activity.get("in_plan_mode", False),
                })

        # Sort: by project, then by spawned_at within project
        agents.sort(key=lambda a: (a["project"], a["id"]))

        payload = {
            "agents": agents,
            "projects": sorted(projects),
        }
        line = json.dumps(payload)
        log.debug("_emit: %d agents, %d projects, %d clients — writing %d bytes to stdout",
                   len(agents), len(projects), len(self._clients), len(line))
        sys.stdout.write(line + "\n")
        sys.stdout.flush()

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
            if state in ("offline", "idle"):
                self._activities.pop(agent_id, None)
            else:
                existing = self._activities.get(agent_id, {})
                new_activity = {
                    "state": state,
                    "tool": msg.get("tool", ""),
                    "ts": time.monotonic(),
                    # Hook reads permission_mode on every event, so in_plan_mode is
                    # always present. Preserve from existing as fallback for safety.
                    "in_plan_mode": msg.get("in_plan_mode", existing.get("in_plan_mode", False)),
                }
                self._activities[agent_id] = new_activity
            log.debug("handle_message: activity agent_id=%s state=%s tool=%s",
                       agent_id, state, msg.get("tool", ""))
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

            enriched = {**msg, "project": project, "terminal_pid": terminal_pid}
            line = json.dumps(enriched)
            log.debug("handle_message: notification pass-through agent_id=%s project=%s terminal_pid=%d",
                       agent_id, project, terminal_pid)
            sys.stdout.write(line + "\n")
            sys.stdout.flush()
            return

        nvim_pid = msg.get("nvim_pid")

        if not msg_type or nvim_pid is None:
            log.warning("handle_message: missing type or nvim_pid in %s", msg)
            return

        log.info("handle_message: type=%s nvim_pid=%s", msg_type, nvim_pid)

        if msg_type == "hello":
            self._clients.setdefault(nvim_pid, {})
            # Resolve terminal PID on first contact (stable for session lifetime)
            if nvim_pid not in self._terminal_pids:
                self._terminal_pids[nvim_pid] = self._resolve_terminal_pid(nvim_pid)
            log.debug("  hello: registered client %s (terminal_pid=%d, total clients: %d)",
                       nvim_pid, self._terminal_pids.get(nvim_pid, 0), len(self._clients))
            # Don't emit: hello registers the client slot but carries no agent data.
            # The subsequent "sync" message will emit with the full initial state.

        elif msg_type == "sync":
            instances = {}
            for inst in msg.get("instances", []):
                buf = inst.get("buf")
                if buf is not None:
                    instances[buf] = inst
            self._clients[nvim_pid] = instances
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
                log.debug("  added: buf=%s active=%s from pid %s", buf, inst.get("active"), nvim_pid)
                self._schedule_emit()
            else:
                log.warning("  added: missing buf from pid %s", nvim_pid)

        elif msg_type == "removed":
            buf = msg.get("buf")
            if nvim_pid in self._clients and buf in self._clients[nvim_pid]:
                del self._clients[nvim_pid][buf]
                self._activities.pop(f"{nvim_pid}_{buf}", None)
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
                    self._activities.pop(f"{nvim_pid}_{buf}", None)
                del self._clients[nvim_pid]
                self._terminal_pids.pop(nvim_pid, None)
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
                self._activities.pop(f"{nvim_pid}_{buf}", None)
            del self._clients[nvim_pid]
            self._terminal_pids.pop(nvim_pid, None)
            self._schedule_emit()
        else:
            log.debug("remove_client: pid=%s not in clients (already removed?)", nvim_pid)

    def reap_stale_activities(self) -> None:
        """Clear activity entries that haven't been updated within the staleness timeout.

        Only reaps activities for agents NOT registered in _clients (orphaned
        entries from crashed sessions or hook race conditions). Registered
        agents are protected — their cleanup is handled by explicit events
        (idle/offline hooks, removed, goodbye, client disconnect).
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
                self._activities.pop(aid, None)
            self._schedule_emit()


bridge = AgentBridge()


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    """Handle a single orchestrator connection."""
    peername = writer.get_extra_info("peername")
    log.info("CLIENT CONNECTED: peername=%s", peername)
    nvim_pid = None
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

            # Track nvim_pid from first message
            if nvim_pid is None:
                nvim_pid = msg.get("nvim_pid")
                log.info("CLIENT identified: nvim_pid=%s", nvim_pid)

            bridge.handle_message(msg)
        log.info("CLIENT EOF: nvim_pid=%s (reader exhausted)", nvim_pid)
    except asyncio.CancelledError:
        log.info("CLIENT CANCELLED: nvim_pid=%s", nvim_pid)
    except Exception as e:
        log.error("CLIENT ERROR: nvim_pid=%s, error=%s", nvim_pid, e)
    finally:
        log.info("CLIENT CLEANUP: nvim_pid=%s, closing writer", nvim_pid)
        writer.close()
        if nvim_pid is not None:
            bridge.remove_client(nvim_pid)


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
    # orchestrator connection). Registered agents are never reaped.
    async def activity_reaper():
        while True:
            await asyncio.sleep(5)  # Check every 5 seconds
            try:
                bridge.reap_stale_activities()
            except Exception as exc:  # noqa: BLE001
                log.error("activity_reaper: unexpected error: %s", exc)
    asyncio.create_task(activity_reaper())

    # Handle signals for clean shutdown
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, lambda: loop.create_task(shutdown(server)))

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
