#!/usr/bin/env python3
"""Read-side backfill for the agent-overview cards.

Given agent session ids as argv, locate each one's Claude transcript
(<claude-config>/projects/*/<session_id>.jsonl) and emit a JSON map
{session_id: {last_prompt, last_messages}} on stdout.

Run by the shell's AgentOverviewService while the overlay is open, so cards show
each agent's recent conversation immediately — even for long-dormant agents the
push-side hook never captured (the push-side only records going forward and is
wiped on a bridge restart; session ids, however, survive, so this read-side path
always has a key to look up). Session ids are globally unique, so a glob across
all project dirs finds the one transcript without needing the agent's cwd.

Best-effort: ids with no transcript (e.g. remote agents, whose transcript lives
on another machine) are simply omitted — the card falls back to the pushed
fields for those.
"""

import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from symmetria_agent_transcript import extract_conversation
except Exception:  # pragma: no cover - defensive: never break the shell's reader
    def extract_conversation(*_args, **_kwargs):
        return {"last_prompt": "", "last_messages": []}

_PROJECTS_DIR = os.path.join(
    os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude"),
    "projects",
)


def _transcript_for(session_id: str) -> str:
    hits = glob.glob(os.path.join(_PROJECTS_DIR, "*", f"{session_id}.jsonl"))
    return hits[0] if hits else ""


def main() -> None:
    out = {}
    for session_id in sys.argv[1:]:
        if not session_id:
            continue
        path = _transcript_for(session_id)
        if not path:
            continue
        convo = extract_conversation(path)
        if convo["last_prompt"] or convo["last_messages"]:
            out[session_id] = convo
    sys.stdout.write(json.dumps(out))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.stdout.write("{}")
