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
import time
from datetime import datetime

# Shared transcript extractor (DRY with the agent-overview read-side reader,
# scripts/agent-overview-transcripts.py). Defensive import: if it can't load,
# the hook still reports activity — it just omits the optional conversation
# fields, so a broken/missing module can never block Claude Code.
try:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from symmetria_agent_transcript import extract_conversation, truncate
    _TRANSCRIPT_OK = True
except Exception:
    _TRANSCRIPT_OK = False

    # The prompt arrives free in the event payload and needs nothing from the
    # shared module but this three-line clip, so keep reporting it even when the
    # import fails — only last_messages (which needs the transcript parser)
    # depends on _TRANSCRIPT_OK.
    def truncate(s, maxlen=280):
        s = " ".join((s or "").split())
        return s if len(s) <= maxlen else s[:maxlen].rstrip() + "…"

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

# Optional raw-payload dump for diagnostic sessions. Enable by exporting
# SYMMETRIA_AGENT_DEBUG_HOOKS=1 in the orchestrator's environment. Captures
# every hook payload verbatim (one JSON line per event) to a sidecar file
# so we can postmortem out-of-order events, recap behavior, and any new
# hook event types Claude Code adds in the future.
_RAW_DUMP_ENABLED = os.environ.get("SYMMETRIA_AGENT_DEBUG_HOOKS", "") == "1"
_RAW_DUMP_PATH = os.path.join(
    os.path.dirname(_LOG_PATH), "agent-hooks-raw.jsonl"
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


def _raw_dump(agent_id: str, hook_name: str, event: dict) -> None:
    """Append the full raw event payload to the sidecar dump file.

    Only fires when SYMMETRIA_AGENT_DEBUG_HOOKS=1. The dump is a JSON-lines
    file — each line contains {ts, agent_id, hook_event_name, payload}.
    Use it to investigate any "stuck on X" symptom without re-running the
    failure case.
    """
    if not _RAW_DUMP_ENABLED:
        return
    try:
        record = {
            "ts": datetime.now().isoformat(timespec="milliseconds"),
            "ts_mono_ns": time.monotonic_ns(),
            "agent_id": agent_id,
            "hook_event_name": hook_name,
            "payload": event,
        }
        with open(_RAW_DUMP_PATH, "a") as f:
            f.write(json.dumps(record) + "\n")
    except Exception:
        pass  # Diagnostics must never break the hook

# Hook event → activity state mapping.
#
# Coverage is intentionally generous: Claude Code adds new hook events over
# time (e.g. PostCompact in 2026, Notification, StopFailure). Mapping them
# explicitly — even when the resulting state is the same as a sibling event
# — avoids "unmapped event" warnings spamming the log AND ensures we don't
# accidentally drop a legitimate state transition because the payload had
# a slightly different hook_event_name than we expected.
EVENT_STATE_MAP = {
    # Session lifecycle
    "SessionStart": "starting",
    "SessionEnd": "offline",
    # Per-turn input
    "UserPromptSubmit": "thinking",
    "UserPromptExpansion": "thinking",  # Claude Code 2026+: prompt-template expansion phase
    # Per-turn output
    "Stop": "idle",
    "StopFailure": "idle",  # Stop attempted but failed — agent is still done
    # Tool use
    "PreToolUse": "working",
    "PostToolUse": "thinking",
    "PostToolUseFailure": "thinking",
    "PostToolBatch": "thinking",  # 2026+: emitted after a batch of tool calls
    "PermissionRequest": "needs_permission",
    "PermissionDenied": "thinking",  # User denied — agent will reconsider
    # Subagents
    "SubagentStart": "working",
    "SubagentStop": "thinking",
    # Context management
    "PreCompact": "thinking",
    "PostCompact": "thinking",  # 2026+: emitted after compaction completes
    # Observer-only events (no state change but explicitly mapped to silence
    # "unmapped event" warnings — they carry no actionable lifecycle info)
    # EXCEPTION: Notification wired with the idle_prompt matcher + argv marker
    # is promoted to "idle" in main() (cancellation fallback — see below).
    "Notification": "",
    "TaskCreated": "",
    "TaskCompleted": "",
    "TeammateIdle": "",
    "FileChanged": "",
    "CwdChanged": "",
    "InstructionsLoaded": "",
    "ConfigChange": "",
    "Elicitation": "",
    "ElicitationResult": "",
    "WorktreeCreate": "",
    "WorktreeRemove": "",
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
        # Friendly urgency: kept at "normal" (matching Stop) rather than "critical"
        # so permission popups don't get the alarming red accent stripe. The agent
        # is blocked but this is routine, not an emergency.
        "urgency": "normal",
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

    # Capture the raw payload BEFORE any filtering — we want the dump to
    # include observer-only and unmapped events too, since those are the
    # most interesting ones for diagnosing "stuck on X" symptoms.
    _raw_dump(agent_id, hook_name, event)

    # Surface unmapped event types loudly. These are events Claude Code
    # added that we haven't classified — worth investigating because they
    # may contain new lifecycle signals we should react to.
    if hook_name not in EVENT_STATE_MAP:
        _hook_log(f"unmapped | agent={agent_id} event={hook_name or '(none)'} keys={sorted(event.keys())}")
        return

    state = EVENT_STATE_MAP[hook_name]

    # Clear-sourced SessionStart → "clearing" state for blink animation (start → stop).
    # Normal SessionStart (startup/resume) keeps "starting" (eye-opening + hold).
    if hook_name == "SessionStart" and event.get("source", "") == "clear":
        state = "clearing"

    # Cancellation detection. Claude Code fires NO hook at the moment of a
    # user interrupt (Esc) — the Stop hook is documented as "does not run if
    # the stoppage occurred due to a user interrupt". Two partial signals
    # exist; both are mapped to idle here (the bridge's claude-CLI
    # reconciliation poll is the catch-all for the remaining gap):
    #
    # 1. Notification(idle_prompt) — "Claude is done and waiting for your
    #    next prompt". Wired in settings.json with matcher "idle_prompt" and
    #    an explicit argv marker so we never have to guess at undocumented
    #    payload fields. Fires after an idle threshold (~60s), so it's a
    #    delayed clear, not an instant one.
    if hook_name == "Notification" and "idle-notification" in sys.argv[1:]:
        state = "idle"

    # 2. PostToolUseFailure with is_interrupt — an Esc that lands mid-tool-call
    #    reportedly surfaces here. The field is NOT in the official docs (as of
    #    2026-06-11), so this is defensive: absent field → unchanged behavior
    #    ("thinking"), and we log loudly when it IS seen so we learn whether
    #    the signal is real. See memory/project_claude_cancel_detection.md.
    if hook_name == "PostToolUseFailure" and event.get("is_interrupt") is True:
        _hook_log(f"interrupt | agent={agent_id} PostToolUseFailure carried is_interrupt=true — mapping to idle")
        state = "idle"

    # Observer-only events have an explicit empty-string mapping — log them
    # at debug-info level (so we know they fired) but don't emit an activity
    # message to the bridge.
    if not state:
        _hook_log(f"observer | agent={agent_id} event={hook_name} (no state change)")
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

    # Wall-clock timestamp from this hook's invocation — used by the bridge
    # to detect out-of-order delivery (async hooks fire in parallel and can
    # race over the socket). We use time.time_ns() rather than monotonic_ns
    # because monotonic clocks aren't comparable across separate processes;
    # CLOCK_REALTIME is shared and good enough for ms-scale ordering.
    event_ts_ns = time.time_ns()

    # Log every invocation — the canonical record of what this hook delivered.
    _hook_log(f"hook | agent={agent_id} event={hook_name} state={state} tool={tool or '-'} plan={plan_mode} ts_ns={event_ts_ns}")

    # Build messages before opening socket
    activity_payload = {
        "type": "activity",
        "agent_id": agent_id,
        # This hook ONLY ever runs for Claude Code (it's wired into Claude's
        # hooks system), so the backend identity is hardcoded here rather than
        # threaded through orchestrator.nvim. Keep the field name/values in sync
        # with the OpenCode reporter (~/.config/opencode/plugin/symmetria-agent.js).
        "agent_type": "claude",
        "state": state,
        "tool": tool,
        "in_plan_mode": plan_mode,
        "hook_event": hook_name,  # passthrough — bridge logs it for diff context
        "event_ts_ns": event_ts_ns,
        # Claude Code session UUID (present in every hook payload). The bridge
        # joins this against `claude agents --json` sessionId to reconcile
        # stuck-busy agents whose cancellation fired no hook.
        "session_id": event.get("session_id", ""),
    }

    # Conversation context for the agent-overview cards (push-side enrichment).
    # Optional fields: the user's prompt comes free from the UserPromptSubmit
    # payload; the recent assistant turns are read from the transcript tail only
    # at turn end (Stop), keeping transcript I/O off the per-tool hot path. The
    # bridge stores both stickily (like session_id) and forwards them in snapshots.
    if hook_name in ("UserPromptSubmit", "UserPromptExpansion"):
        prompt = event.get("prompt", "")
        if isinstance(prompt, str) and prompt.strip():
            activity_payload["last_prompt"] = truncate(prompt.strip(), 280)
    if _TRANSCRIPT_OK and hook_name in ("Stop", "StopFailure"):
        convo = extract_conversation(event.get("transcript_path", ""))
        if convo.get("last_messages"):
            activity_payload["last_messages"] = convo["last_messages"]

    activity_msg = json.dumps(activity_payload)
    notif = _build_notification(hook_name, event, agent_id)

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(1.0)
        sock.connect(SOCKET_PATH)
        sock.sendall((activity_msg + "\n").encode())
        if notif:
            sock.sendall((json.dumps(notif) + "\n").encode())


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        _hook_log(f"exception | {type(e).__name__}: {e}")
