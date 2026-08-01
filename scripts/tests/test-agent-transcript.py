#!/usr/bin/env python3
"""Test harness for symmetria_agent_transcript.extract_conversation.

The parser is coupled to Claude Code's on-disk transcript format, which drifts
between releases, and it sits on the critical path of two callers — one of them
the agent hook that runs inside every Claude Code turn. These fixtures pin the
behaviours that a format change would silently break, above all the fact that
the `user` role carries far more than user prompts.

Self-contained: fixtures are written to a temp file and cleaned up on exit.

Usage: ./test-agent-transcript.py [-v]
  -v  Verbose mode: print each passing case as well as failures
"""

import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from symmetria_agent_transcript import extract_conversation, truncate  # noqa: E402

VERBOSE = "-v" in sys.argv
_failures = []


# ── Fixture helpers ──────────────────────────────────────────────────────────

def user(text, **extra):
    return dict({"type": "user", "message": {"role": "user", "content": text}}, **extra)


def assistant(text):
    return {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": text}]}}


def last_prompt_record(text):
    return {"type": "last-prompt", "lastPrompt": text, "sessionId": "s1"}


def run(entries):
    """Write entries as JSONL, parse them, and return the extraction result."""
    with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as f:
        for e in entries:
            f.write(json.dumps(e) + "\n")
        path = f.name
    try:
        return extract_conversation(path)
    finally:
        os.unlink(path)


def check(name, actual, expected):
    if actual == expected:
        if VERBOSE:
            print(f"  ok   {name}")
    else:
        _failures.append(name)
        print(f"  FAIL {name}\n         expected: {expected!r}\n         actual:   {actual!r}")


# ── Cases ────────────────────────────────────────────────────────────────────

def test_plain_exchange():
    r = run([user("what does this do"), assistant("It parses transcripts.")])
    check("plain: prompt", r["last_prompt"], "what does this do")
    check("plain: messages", r["last_messages"], ["It parses transcripts."])


def test_last_prompt_record_wins():
    """The authoritative record beats any user-role turn, wherever it appears."""
    r = run([
        user("stale earlier prompt"),
        assistant("ok"),
        last_prompt_record("the real prompt"),
    ])
    check("last-prompt record wins", r["last_prompt"], "the real prompt")


def test_envelopes_are_not_prompts():
    """User-role envelopes must never surface as the prompt (see _is_real_prompt)."""
    for envelope in [
        "<task-notification>agent finished</task-notification>",
        "<system-reminder>context follows</system-reminder>",
        "<command-name>/clear</command-name>",
        "<local-command-stdout>done</local-command-stdout>",
        "<bash-input>ls</bash-input>",
        "[Request interrupted by user]",
    ]:
        r = run([user("the real prompt"), assistant("ok"), user(envelope)])
        check(f"envelope rejected: {envelope[:24]}", r["last_prompt"], "the real prompt")


def test_ismeta_rejected():
    r = run([user("the real prompt"), user("injected caveat text", isMeta=True)])
    check("isMeta rejected", r["last_prompt"], "the real prompt")


def test_tool_blocks_skipped():
    """tool_use / tool_result / thinking blocks carry no previewable text."""
    r = run([
        user([{"type": "tool_result", "tool_use_id": "t1", "content": "file contents"}]),
        {"type": "assistant", "message": {"role": "assistant", "content": [
            {"type": "thinking", "thinking": "hidden reasoning"},
            {"type": "tool_use", "id": "t2", "name": "Read", "input": {}},
            {"type": "text", "text": "visible answer"},
        ]}},
        last_prompt_record("real prompt"),
    ])
    check("tool blocks: prompt", r["last_prompt"], "real prompt")
    check("tool blocks: messages", r["last_messages"], ["visible answer"])


def test_keeps_last_three_assistant_turns():
    r = run([assistant(f"turn {i}") for i in range(1, 6)])
    check("keeps newest 3", r["last_messages"], ["turn 3", "turn 4", "turn 5"])


def test_partial_first_line_from_tail_seek():
    """A >256 KB transcript is read from a mid-file offset; the split line must
    not break parsing of everything after it."""
    filler = [assistant("x" * 2000) for _ in range(200)]  # ~400 KB, past the window
    r = run(filler + [assistant("final answer"), last_prompt_record("real prompt")])
    check("tail seek: prompt", r["last_prompt"], "real prompt")
    check("tail seek: last message", r["last_messages"][-1], "final answer")


def test_malformed_input_is_survivable():
    check("missing path", extract_conversation(""), {"last_prompt": "", "last_messages": []})
    check("nonexistent path", extract_conversation("/nonexistent/x.jsonl"), {"last_prompt": "", "last_messages": []})
    r = run([{"garbage": True}, "not-an-object", user("real prompt")])
    check("garbage lines skipped", r["last_prompt"], "real prompt")


def test_truncate():
    check("truncate: collapses whitespace", truncate("a  b\n c"), "a b c")
    check("truncate: clips with ellipsis", truncate("abcdef", 3), "abc…")
    check("truncate: leaves short strings", truncate("abc", 10), "abc")
    check("truncate: prompt is clipped", run([user("y" * 400)])["last_prompt"], "y" * 280 + "…")


# ── Runner ───────────────────────────────────────────────────────────────────

def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for t in tests:
        if VERBOSE:
            print(t.__name__)
        t()
    if _failures:
        print(f"\n{len(_failures)} check(s) failed")
        return 1
    print(f"All checks passed ({len(tests)} test functions)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
