#!/usr/bin/env python3
"""Symmetria Agent Hook — reports Claude Code lifecycle events to the agent bridge.

Invoked by Claude Code's hooks system (async: true) on every lifecycle event.
Reads SYMMETRIA_AGENT_ID from the environment (set by orchestrator.nvim) and
sends activity state to the bridge's Unix socket.

Exit code is always 0 — hook failures must never block Claude Code.
"""

import json
import os
import socket
import sys

SOCKET_PATH = f"/run/user/{os.getuid()}/symmetria-agents.sock"

# Hook event → activity state mapping
EVENT_STATE_MAP = {
    "SessionStart": "starting",
    "UserPromptSubmit": "thinking",
    "PreToolUse": "working",
    "PostToolUse": "thinking",
    "PostToolUseFailure": "thinking",
    "PermissionRequest": "needs_permission",
    "Stop": "idle",
    "SessionEnd": "offline",
}

# Tool name → human-readable display name
TOOL_DISPLAY_NAMES = {
    "Edit": "Editing",
    "Write": "Writing",
    "Read": "Reading",
    "Bash": "Running",
    "Glob": "Searching",
    "Grep": "Searching",
    "Task": "Delegating",
    "WebFetch": "Fetching",
    "WebSearch": "Searching",
    "NotebookEdit": "Editing",
    "EnterPlanMode": "Planning",
    "AskUserQuestion": "Asking",
}


def main():
    # Bail silently if not spawned by orchestrator
    agent_id = os.environ.get("SYMMETRIA_AGENT_ID", "")
    if not agent_id:
        return

    # Read hook event JSON from stdin
    raw = sys.stdin.read().strip()
    if not raw:
        return

    event = json.loads(raw)
    hook_name = event.get("hook_event_name", "")

    state = EVENT_STATE_MAP.get(hook_name, "")
    if not state:
        return

    # Resolve tool display name for PreToolUse
    tool = ""
    if hook_name == "PreToolUse":
        tool_name = event.get("tool_name", "")
        tool = TOOL_DISPLAY_NAMES.get(tool_name, tool_name)

    # Send to bridge socket
    msg = json.dumps({
        "type": "activity",
        "agent_id": agent_id,
        "state": state,
        "tool": tool,
    })

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(1.0)
    sock.connect(SOCKET_PATH)
    sock.sendall((msg + "\n").encode())
    sock.close()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # Never fail — always exit 0
