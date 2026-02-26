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
import sys
from pathlib import Path

SOCKET_PATH = Path(f"/run/user/{os.getuid()}/symmetria-agents.sock")

# Debug logging to stderr (stdout is reserved for QML SplitParser data)
logging.basicConfig(
    stream=sys.stderr,
    level=logging.DEBUG,
    format="[bridge.py %(levelname)s] %(message)s",
)
log = logging.getLogger("agent-bridge")


class AgentBridge:
    """Aggregates agent state from all connected orchestrator instances."""

    def __init__(self):
        # {nvim_pid: {buf: instance_data, ...}}
        self._clients: dict[int, dict[int, dict]] = {}

    def _emit(self) -> None:
        """Write consolidated state to stdout (consumed by QML SplitParser)."""
        agents = []
        projects = set()

        for nvim_pid, instances in self._clients.items():
            for buf, inst in instances.items():
                project = inst.get("project", "unknown")
                projects.add(project)
                agents.append({
                    "id": f"{nvim_pid}_{buf}",
                    "nvim_pid": nvim_pid,
                    "buf": buf,
                    "project": project,
                    "title": inst.get("title", ""),
                    "color_idx": inst.get("color_idx", 0),
                    "dangerous": inst.get("dangerous", False),
                    "active": inst.get("active", False),
                    "spawn_type": inst.get("spawn_type", "fresh"),
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

    def handle_message(self, msg: dict) -> None:
        """Process a single JSON message from an orchestrator client."""
        msg_type = msg.get("type")
        nvim_pid = msg.get("nvim_pid")

        if not msg_type or not nvim_pid:
            log.warning("handle_message: missing type or nvim_pid in %s", msg)
            return

        log.info("handle_message: type=%s nvim_pid=%s", msg_type, nvim_pid)

        if msg_type == "hello":
            self._clients.setdefault(nvim_pid, {})
            log.debug("  hello: registered client %s (total clients: %d)", nvim_pid, len(self._clients))
            # Don't emit on hello alone — wait for sync

        elif msg_type == "sync":
            instances = {}
            for inst in msg.get("instances", []):
                buf = inst.get("buf")
                if buf is not None:
                    instances[buf] = inst
            self._clients[nvim_pid] = instances
            log.debug("  sync: %d instances from pid %s", len(instances), nvim_pid)
            self._emit()

        elif msg_type == "added":
            inst = msg.get("instance", {})
            buf = inst.get("buf")
            if buf is not None:
                self._clients.setdefault(nvim_pid, {})[buf] = inst
                log.debug("  added: buf=%s from pid %s", buf, nvim_pid)
                self._emit()

        elif msg_type == "removed":
            buf = msg.get("buf")
            if nvim_pid in self._clients and buf in self._clients[nvim_pid]:
                del self._clients[nvim_pid][buf]
                log.debug("  removed: buf=%s from pid %s", buf, nvim_pid)
                self._emit()

        elif msg_type == "updated":
            buf = msg.get("buf")
            if nvim_pid in self._clients and buf in self._clients[nvim_pid]:
                # Merge updated fields
                for key in ("title", "color_idx", "dangerous", "spawn_type"):
                    if key in msg:
                        self._clients[nvim_pid][buf][key] = msg[key]
                log.debug("  updated: buf=%s from pid %s", buf, nvim_pid)
                self._emit()

        elif msg_type == "focus":
            buf = msg.get("buf")
            if nvim_pid in self._clients:
                # Clear active on all, set on focused
                for b, inst in self._clients[nvim_pid].items():
                    inst["active"] = (b == buf)
                log.debug("  focus: buf=%s from pid %s", buf, nvim_pid)
                self._emit()

        elif msg_type == "goodbye":
            if nvim_pid in self._clients:
                del self._clients[nvim_pid]
                log.debug("  goodbye: removed client %s (remaining: %d)", nvim_pid, len(self._clients))
                self._emit()
        else:
            log.warning("  unknown message type: %s", msg_type)

    def remove_client(self, nvim_pid: int) -> None:
        """Remove all state for a disconnected client."""
        if nvim_pid in self._clients:
            count = len(self._clients[nvim_pid])
            log.info("remove_client: dropping pid=%s (%d instances), remaining clients: %d",
                     nvim_pid, count, len(self._clients) - 1)
            del self._clients[nvim_pid]
            self._emit()
        else:
            log.debug("remove_client: pid=%s not in clients (already removed?)", nvim_pid)


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


def cleanup_socket():
    """Remove socket file on exit."""
    try:
        SOCKET_PATH.unlink(missing_ok=True)
    except OSError:
        pass


async def main():
    # Clean up stale socket
    log.info("STARTING: cleaning stale socket at %s", SOCKET_PATH)
    SOCKET_PATH.unlink(missing_ok=True)
    atexit.register(cleanup_socket)

    server = await asyncio.start_unix_server(handle_client, path=str(SOCKET_PATH))
    # Ensure socket is accessible
    SOCKET_PATH.chmod(0o600)
    log.info("LISTENING on %s (pid=%d)", SOCKET_PATH, os.getpid())

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
    log.info("SHUTDOWN: server closed, cancelling %d tasks", len(asyncio.all_tasks()) - 1)
    # Socket cleanup handled by atexit handler
    for task in asyncio.all_tasks():
        if task is not asyncio.current_task():
            task.cancel()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit):
        cleanup_socket()
