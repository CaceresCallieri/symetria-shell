#!/usr/bin/env python3
"""Symmetria Agent Hook — reports Claude Code lifecycle events to the agent bridge.

Invoked by Claude Code's hooks system (async: true) on every lifecycle event.
Reads SYMMETRIA_AGENT_ID from the environment (set by orchestrator.nvim) and
sends activity state to the bridge's Unix socket.

For attention-requiring events (Stop, PermissionRequest, Notification subtypes),
a second "notification" message is sent on the same socket
connection. The bridge enriches it with project/workspace info and AgentService
spawns notify-send.

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

# Notification subtypes (for the "Notification" hook event).
NOTIFICATION_SUBTYPES = {
    "permission_prompt": {"title_suffix": "Permission Needed", "urgency": "critical"},
    "elicitation_dialog": {"title_suffix": "Question", "urgency": "normal"},
    "idle_prompt": {"title_suffix": "Waiting", "urgency": "normal"},
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

    # Notification event subtypes
    if hook_name == "Notification":
        notification_type = event.get("notification_type", "")
        if notification_type not in NOTIFICATION_SUBTYPES:
            return None  # e.g., auth_success — not notification-worthy

        info = NOTIFICATION_SUBTYPES[notification_type]
        raw_message = event.get("message", "")
        fallback = {
            "permission_prompt": "Needs your permission to proceed.",
            "elicitation_dialog": "Has a question for you.",
            "idle_prompt": "Waiting for your input.",
        }

        return {
            "type": "notification",
            "agent_id": agent_id,
            "event": hook_name,
            "title_suffix": info["title_suffix"],
            "message": raw_message or fallback.get(notification_type, ""),
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

    # Notification hook events have no activity state — they're notification-only.
    # All other events must have a mapped state to proceed.
    if not state and hook_name != "Notification":
        return

    # Detect plan mode from permission_mode field (present in all hook events).
    # This is reliable regardless of how plan mode was entered (Shift+Tab, /plan,
    # --permission-mode plan, or AI-initiated EnterPlanMode tool).
    # EnterPlanMode/ExitPlanMode tools do NOT reliably fire PreToolUse hooks.
    plan_mode = event.get("permission_mode", "") == "plan"

    # Resolve tool display name for tool-bearing events
    tool = ""
    if hook_name == "PreToolUse":
        tool_name = event.get("tool_name", "")
        tool = TOOL_DISPLAY_NAMES.get(tool_name, tool_name)
    elif hook_name == "SubagentStart":
        tool = "Delegating"

    # Build messages before opening socket
    activity_msg = None
    if state:
        activity_msg = json.dumps({
            "type": "activity",
            "agent_id": agent_id,
            "state": state,
            "tool": tool,
            "in_plan_mode": plan_mode,
        })
    notif = _build_notification(hook_name, event, agent_id)

    # Only connect if there is something to send
    if not activity_msg and not notif:
        return

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(1.0)
    sock.connect(SOCKET_PATH)

    if activity_msg:
        sock.sendall((activity_msg + "\n").encode())
    if notif:
        sock.sendall((json.dumps(notif) + "\n").encode())

    sock.close()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # Never fail — always exit 0
