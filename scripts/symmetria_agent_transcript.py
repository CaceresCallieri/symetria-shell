"""Shared transcript extraction for Symmetria agent tooling.

Used by BOTH the Claude hook (push-side, at Stop — scripts/symmetria-agent-hook.py)
and the agent-overview read-side backfill (scripts/agent-overview-transcripts.py).
Pure stdlib and fully defensive: any error yields empty results so neither caller
can be broken by a malformed or partially-written transcript.
"""

import json


def truncate(s: str, maxlen: int = 280) -> str:
    """Collapse whitespace and clip to maxlen chars with an ellipsis."""
    s = " ".join((s or "").split())
    return s if len(s) <= maxlen else s[:maxlen].rstrip() + "…"


def _text_of(content) -> str:
    """Flatten a message's content to its plain text, skipping tool blocks."""
    if isinstance(content, list):
        return " ".join(
            b.get("text", "")
            for b in content
            if isinstance(b, dict) and b.get("type") == "text"
        ).strip()
    if isinstance(content, str):
        return content.strip()
    return ""


def extract_conversation(transcript_path: str, n_assistant: int = 3, maxlen: int = 280) -> dict:
    """Return {'last_prompt', 'last_messages'} from a Claude transcript JSONL.

    last_prompt   — the most recent user text turn (truncated).
    last_messages — up to the last n_assistant assistant text turns (truncated),
                    in chronological order (oldest→newest).

    Only `text` blocks are surfaced; tool_use / tool_result blocks (and the
    user-role envelopes that merely carry tool results) are skipped. Reads only
    the tail (~256 KB) so large transcripts stay cheap. Any failure (missing
    file, parse error, partial line) yields the empty result.
    """
    result = {"last_prompt": "", "last_messages": []}
    if not transcript_path:
        return result
    try:
        with open(transcript_path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            start = max(0, size - 256 * 1024)
            f.seek(start)
            chunk = f.read()
        lines = chunk.decode("utf-8", "replace").split("\n")
        if start > 0 and lines:
            lines = lines[1:]  # drop the partial first line from the mid-file seek
        assistants = []
        last_prompt = ""
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            typ = obj.get("type")
            message = obj.get("message")
            if not isinstance(message, dict):
                continue
            role = message.get("role")
            text = _text_of(message.get("content", ""))
            if not text:
                continue
            if typ == "assistant" and role == "assistant":
                assistants.append(truncate(text, maxlen))
            elif typ == "user" and role == "user":
                last_prompt = truncate(text, maxlen)
        result["last_messages"] = assistants[-n_assistant:]
        result["last_prompt"] = last_prompt
        return result
    except Exception:
        return result
