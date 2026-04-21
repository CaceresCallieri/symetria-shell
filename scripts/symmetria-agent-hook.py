#!/usr/bin/env python3
"""Symmetria Agent Hook — reports Claude Code lifecycle events to the agent bridge.

Invoked by Claude Code's hooks system (async: true) on every lifecycle event.
Reads SYMMETRIA_AGENT_ID from the environment (set by orchestrator.nvim) and
sends an activity-state message to the bridge's Unix socket.

For events requiring user attention (Stop, PermissionRequest), a second
"notification" message is sent in the same write batch. The bridge enriches
it with project/workspace info; AgentService spawns notify-send.

Exit code is always 0 — hook failures must never block Claude Code.
"""

import json
import os
import socket
import sys
from datetime import datetime

SOCKET_PATH = os.environ.get(
    "SYMMETRIA_AGENT_SOCKET",
    f"/run/user/{os.getuid()}/symmetria-agents.sock",
)

# Unified log shared with Symmetria.Logger (C++), QML services, and bash.
# Format matches plugin/src/Symmetria/logger.cpp exactly so all sources
# interleave in a single timeline at ~/.local/state/symmetria/debug.log.
_LOG_PATH = os.environ.get("SYMMETRIA_DEBUG_LOG") or os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
    "symmetria", "debug.log",
)


def _hook_log(msg: str) -> None:
    """Append a line to the unified debug log. Never raises."""
    try:
        os.makedirs(os.path.dirname(_LOG_PATH), exist_ok=True)
        now = datetime.now()
        ts = f"{now.strftime('%H:%M:%S')}.{now.microsecond // 1000:03d}"
        with open(_LOG_PATH, "a") as f:
            f.write(f"{ts} [py:hook] {msg}\n")
    except Exception:
        pass  # Logging must never break the hook

# Hook event → activity state mapping
EVENT_STATE_MAP = {
    "SessionStart": "starting",
    "UserPromptSubmit": "thinking",
    "PreToolUse": "working",
    "PostToolUse": "thinking",
    "PostToolUseFailure": "thinking",
    "PermissionRequest": "needs_permission",
    "SubagentStart": "working",
    "SubagentStop": "thinking",
    "PreCompact": "thinking",
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
    "UrlFetch": "Fetching",
    "WebSearch": "Searching",
    "NotebookEdit": "Editing",
    "AskUserQuestion": "Asking",
    "ExitPlanMode": "Planning",
    "TodoWrite": "Organizing",
    "TaskCreate": "Organizing",
    "TaskUpdate": "Organizing",
    "TaskList": "Organizing",
    "TaskGet": "Organizing",
}

# Events that warrant a desktop notification (sent as a second message after activity).
# Only events where the agent is BLOCKED and needs human attention belong here.
# PostToolUseFailure is intentionally excluded — the agent recovers on its own.
NOTIFICATION_EVENTS = {
    "Stop": {
        "title_suffix": "Ready",
        "message": "Task completed. Awaiting your input.",
        "urgency": "normal",
    },
    "PermissionRequest": {
        "title_suffix": "Permission Required",
        "urgency": "critical",
    },
}


def _build_notification(hook_name: str, event: dict, agent_id: str) -> dict | None:
    """Build a notification message if the event warrants user attention."""

    # Direct event notifications (Stop, PermissionRequest)
    if hook_name in NOTIFICATION_EVENTS:
        info = NOTIFICATION_EVENTS[hook_name]
        message = info.get("message", "")

        # PermissionRequest: extract tool details
        if hook_name == "PermissionRequest":
            tool_name = event.get("tool_name", "a tool")
            tool_command = event.get("tool_input", {}).get("command", "")
            if tool_command:
                if len(tool_command) > 50:
                    message = f"Approve {tool_name}: {tool_command[:50]}..."
                else:
                    message = f"Approve {tool_name}: {tool_command}"
            else:
                message = f"Needs permission to use {tool_name}."

        return {
            "type": "notification",
            "agent_id": agent_id,
            "event": hook_name,
            "title_suffix": info["title_suffix"],
            "message": message,
            "urgency": info["urgency"],
        }

    return None


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

    # Clear-sourced SessionStart → "clearing" state for blink animation (start → stop).
    # Normal SessionStart (startup/resume) keeps "starting" (eye-opening + hold).
    if hook_name == "SessionStart" and event.get("source", "") == "clear":
        state = "clearing"

    # All events must have a mapped state to proceed.
    if not state:
        return

    # Detect plan mode from permission_mode field (present in all hook events).
    # This is reliable regardless of how plan mode was entered (Shift+Tab, /plan,
    # --permission-mode plan, or AI-initiated EnterPlanMode tool).
    # EnterPlanMode/ExitPlanMode tools do NOT reliably fire PreToolUse hooks.
    plan_mode = event.get("permission_mode", "") == "plan"

    # Resolve tool display name for tool-bearing events
    tool = ""
    if hook_name in ("PreToolUse", "PermissionRequest"):
        tool_name = event.get("tool_name", "")
        tool = TOOL_DISPLAY_NAMES.get(tool_name, tool_name)
    elif hook_name == "SubagentStart":
        tool = "Delegating"  # no tool_name in payload; label directly

    # Log every invocation — the canonical record of what this hook delivered.
    _hook_log(f"hook | agent={agent_id} event={hook_name} state={state} tool={tool or '-'} plan={plan_mode}")

    # Build messages before opening socket
    activity_msg = json.dumps({
        "type": "activity",
        "agent_id": agent_id,
        "state": state,
        "tool": tool,
        "in_plan_mode": plan_mode,
    })
    notif = _build_notification(hook_name, event, agent_id)

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(1.0)
    sock.connect(SOCKET_PATH)

    sock.sendall((activity_msg + "\n").encode())
    if notif:
        sock.sendall((json.dumps(notif) + "\n").encode())

    sock.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        _hook_log(f"exception | {type(e).__name__}: {e}")
