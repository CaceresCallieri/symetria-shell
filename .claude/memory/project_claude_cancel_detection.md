---
name: claude-cancel-detection
description: "Why canceled Claude Code turns leave dashboard stuck \"busy\" + verified signals for a fix (claude agents --json, idle_prompt, is_interrupt)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 68dd9756-bb96-43b6-83c4-8328249c8878
---

Deep research verified 2026-06-11 (docs + changelog + GitHub issues, 3-vote adversarial verification):

**Root cause:** Claude Code's `Stop` hook explicitly does NOT fire on user interrupt (Esc/Ctrl-C) — official docs: "Does not run if the stoppage occurred due to a user interrupt." No hook, OTEL event, or transcript marker fires at the moment of cancellation. Feature requests #9516 / #45289 (interrupt hook) remain open as of 2026-06-11.

**Why OpenCode works:** its plugin bus emits first-class `session.idle` / `session.status` events regardless of how the turn ended; our `symmetria-agent.js` already listens to `session.idle`.

**Usable signals for Claude Code (verified):**
- `claude agents --json` (CLI v2.1.145+; `waitingFor` field since v2.1.162) — pollable per-session `pid`, `cwd`, `sessionId`, `status` (idle/waiting/running). Strongest reconciliation source; local sessions only; fields present only "when set". Remote SSH-tunneled agents need a different path.
- `Notification` hook `idle_prompt` matcher ("Claude is done and waiting for your next prompt") — hook-native idle signal but delayed (~60s idle threshold, undocumented).
- `PostToolUseFailure` may carry `is_interrupt: true` when Esc lands mid-tool-call — NOT fully verified (1-2 vote); test empirically before relying on it. Only covers mid-tool interrupts, not mid-streaming.
- `UserPromptSubmit` as turn-boundary reset (already wired → `thinking`). Caveat: check whether queued/steering messages mid-turn fire it falsely.

**Accepted pattern:** layered — optimistic busy-set from hooks, clear on terminal hooks, plus bridge-side watchdog reconciling via `claude agents --json` + PID liveness + generous timeout. Even Anthropic's own agents view had a 30s stale-busy bug (fixed v2.1.172), confirming poll+timeout reconciliation is the norm.

Fix would land in `scripts/agent-bridge.py` watchdog (currently log-only, see [[agent-bridge]] diagnostics in docs/agent-state-diagnostics.md) — hook script may need to report the claude process PID so the bridge can join against `claude agents --json` output.
