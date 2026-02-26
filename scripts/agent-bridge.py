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
import sys
from pathlib import Path

SOCKET_PATH = Path(f"/run/user/{os.getuid()}/symmetria-agents.sock")


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
        sys.stdout.write(json.dumps(payload) + "\n")
        sys.stdout.flush()

    def handle_message(self, msg: dict) -> None:
        """Process a single JSON message from an orchestrator client."""
        msg_type = msg.get("type")
        nvim_pid = msg.get("nvim_pid")

        if not msg_type or not nvim_pid:
            return

        if msg_type == "hello":
            self._clients.setdefault(nvim_pid, {})
            # Don't emit on hello alone — wait for sync

        elif msg_type == "sync":
            instances = {}
            for inst in msg.get("instances", []):
                buf = inst.get("buf")
                if buf is not None:
                    instances[buf] = inst
            self._clients[nvim_pid] = instances
            self._emit()

        elif msg_type == "added":
            inst = msg.get("instance", {})
            buf = inst.get("buf")
            if buf is not None:
                self._clients.setdefault(nvim_pid, {})[buf] = inst
                self._emit()

        elif msg_type == "removed":
            buf = msg.get("buf")
            if nvim_pid in self._clients and buf in self._clients[nvim_pid]:
                del self._clients[nvim_pid][buf]
                self._emit()

        elif msg_type == "updated":
            buf = msg.get("buf")
            if nvim_pid in self._clients and buf in self._clients[nvim_pid]:
                # Merge updated fields
                for key in ("title", "color_idx", "dangerous", "spawn_type"):
                    if key in msg:
                        self._clients[nvim_pid][buf][key] = msg[key]
                self._emit()

        elif msg_type == "focus":
            buf = msg.get("buf")
            if nvim_pid in self._clients:
                # Clear active on all, set on focused
                for b, inst in self._clients[nvim_pid].items():
                    inst["active"] = (b == buf)
                self._emit()

        elif msg_type == "goodbye":
            if nvim_pid in self._clients:
                del self._clients[nvim_pid]
                self._emit()

    def remove_client(self, nvim_pid: int) -> None:
        """Remove all state for a disconnected client."""
        if nvim_pid in self._clients:
            del self._clients[nvim_pid]
            self._emit()


bridge = AgentBridge()


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    """Handle a single orchestrator connection."""
    nvim_pid = None
    try:
        async for line in reader:
            text = line.decode("utf-8", errors="replace").strip()
            if not text:
                continue
            try:
                msg = json.loads(text)
            except json.JSONDecodeError:
                continue

            # Track nvim_pid from first message
            if nvim_pid is None:
                nvim_pid = msg.get("nvim_pid")

            bridge.handle_message(msg)
    except asyncio.CancelledError:
        pass
    except Exception as e:
        print(f"[agent-bridge] client error: {e}", file=sys.stderr)
    finally:
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
    SOCKET_PATH.unlink(missing_ok=True)
    atexit.register(cleanup_socket)

    server = await asyncio.start_unix_server(handle_client, path=str(SOCKET_PATH))
    # Ensure socket is accessible
    SOCKET_PATH.chmod(0o600)

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

    server.close()
    await server.wait_closed()
    # Socket cleanup handled by atexit handler
    for task in asyncio.all_tasks():
        if task is not asyncio.current_task():
            task.cancel()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit):
        cleanup_socket()
