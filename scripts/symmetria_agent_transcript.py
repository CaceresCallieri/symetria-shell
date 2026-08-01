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


def _is_real_prompt(text: str) -> bool:
    """Reject user-role turns that are not something the user actually typed.

    The `user` role carries far more than prompts: tool results, hook output,
    slash-command envelopes, and injected context all arrive under it. Measured
    against the transcripts on this machine, taking the last user turn verbatim
    produced a bogus preview about a quarter of the time — `<task-notification>`,
    `<system-reminder>`, `<local-command-stdout>`, `<command-name>/clear</...>`,
    `[Request interrupted by user]`. `isMeta` does NOT discriminate: most of
    those envelopes carry `isMeta: false`. Hence this shape check.
    """
    return bool(text) and not text.startswith("<") and not text.startswith("[Request interrupted")


def extract_conversation(transcript_path: str, n_assistant: int = 3, maxlen: int = 280) -> dict:
    """Return {'last_prompt', 'last_messages'} from a Claude transcript JSONL.

    last_prompt   — the user's most recent prompt (truncated).
    last_messages — up to the last n_assistant assistant text turns (truncated),
                    in chronological order (oldest→newest).

    last_prompt is taken from Claude Code's own `last-prompt` record when the
    tail contains one (it does for ~98% of transcripts here), which is
    authoritative and needs no heuristics. Older transcripts without that record
    fall back to the newest plausible user text turn — see _is_real_prompt.

    Only `text` blocks are surfaced; tool_use / tool_result / thinking blocks
    (and the user-role envelopes that merely carry tool results) are skipped.
    Reads only the tail (~256 KB) so large transcripts stay cheap. Any failure
    (missing file, parse error, partial line) yields the empty result.
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
        last_prompt = ""       # authoritative: from a `last-prompt` record
        fallback_prompt = ""   # heuristic: newest plausible user text turn
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            # A line can be valid JSON without being a record (a bare string or
            # number). Skipping it must not abort the whole read — the outer
            # except would otherwise swallow the AttributeError and drop every
            # remaining line along with it.
            if not isinstance(obj, dict):
                continue
            typ = obj.get("type")
            if typ == "last-prompt":
                candidate = obj.get("lastPrompt")
                if isinstance(candidate, str) and candidate.strip():
                    last_prompt = truncate(candidate, maxlen)
                continue
            message = obj.get("message")
            if not isinstance(message, dict):
                continue
            role = message.get("role")
            text = _text_of(message.get("content", ""))
            if not text:
                continue
            if typ == "assistant" and role == "assistant":
                assistants.append(truncate(text, maxlen))
            elif typ == "user" and role == "user" and not obj.get("isMeta"):
                if _is_real_prompt(text):
                    fallback_prompt = truncate(text, maxlen)
        result["last_messages"] = assistants[-n_assistant:]
        result["last_prompt"] = last_prompt or fallback_prompt
        return result
    except Exception:
        return result
