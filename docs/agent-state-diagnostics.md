# Agent State Diagnostics

Symmetria's agent bar reflects every Claude Code agent's lifecycle (idle / thinking / working / needs_permission / etc.) by chaining three independent processes:

```
Claude Code hooks ──► symmetria-agent-hook.py ──► agent-bridge.py ──► QML AgentService
       (per event)        (per agent fork)          (singleton)         (singleton)
```

When the bar shows a stale state ("stuck on working" being the canonical complaint), the failure can be in any of the four hops. This document describes the diagnostic instrumentation built into each layer and how to use it.

## TL;DR — Investigating a "stuck" symptom

1. Reproduce the symptom. Note the wall-clock time and which agent is stuck.
2. Capture the bridge's view: `pkill -USR1 -f agent-bridge.py` writes a full snapshot to `~/.local/state/symmetria/agent-bridge-diagnostic.json`.
3. Capture QML's view: `symmetria shell agentbar diagnose` returns a JSON snapshot of what the rendering layer believes.
4. Diff the two snapshots:
   - If the **bridge** has the agent in `working` and QML matches → the hook layer never sent a `Stop`. Check `~/.local/state/symmetria/agent-hooks-raw.jsonl` if `SYMMETRIA_AGENT_DEBUG_HOOKS=1` was set, or grep `[py:hook]` in the unified log around the failure time.
   - If the **bridge** has the agent in `idle`/cleared but QML still shows `working` → it's a QML rendering bug. The QML stuck watchdog will log `STUCK WORKING | <id>` to `qml,agent` after 120s.
   - If the bridge log shows `OUT-OF-ORDER` warnings near the failure → an async hook race is the cause. See `Out-of-order events`.

## Layer 1 — `symmetria-agent-hook.py`

Spawned by Claude Code on every lifecycle event. Configured in `~/.claude/settings.json` under `hooks` with `"async": true`, which means **multiple hook invocations can run in parallel** for back-to-back events.

### Event mapping

`EVENT_STATE_MAP` covers the full Claude Code 2026 hook surface. Events fall into three groups:

| Group | Hook events | Mapped state |
|-------|-------------|--------------|
| Working | `PreToolUse`, `SubagentStart` | `working` |
| Thinking | `UserPromptSubmit`, `UserPromptExpansion`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `PermissionDenied`, `SubagentStop`, `PreCompact`, `PostCompact` | `thinking` |
| Terminal | `Stop`, `StopFailure`, `SessionEnd` | `idle` / `offline` |
| Special | `SessionStart`, `PermissionRequest` | `starting` / `needs_permission` |
| Observer | `Notification`, `TaskCreated`, `TaskCompleted`, `TeammateIdle`, `FileChanged`, `CwdChanged`, `InstructionsLoaded`, `ConfigChange`, `Elicitation`, `ElicitationResult`, `WorktreeCreate`, `WorktreeRemove` | _(no state change)_ |

Observer-only events have an explicit empty-string mapping, NOT a missing entry. This distinction matters: an unknown event logs an `unmapped |` warning, while an observer event logs an `observer |` info line. If Claude Code adds a new event we haven't classified, the unmapped-warning surfaces it the first time it fires.

### Raw payload capture

Set `SYMMETRIA_AGENT_DEBUG_HOOKS=1` in the orchestrator's environment before launching Claude Code. Every hook payload is then appended verbatim (one JSON line per event) to:

```
~/.local/state/symmetria/agent-hooks-raw.jsonl
```

Each record contains `{ts, ts_mono_ns, agent_id, hook_event_name, payload}`. This is the ground-truth record of what Claude Code actually sent, including fields the hook script chose not to forward.

### Per-event timestamp

Every activity message now carries `event_ts_ns` (CLOCK_REALTIME, nanoseconds). The bridge uses it to detect out-of-order delivery. The clock is process-shared (CLOCK_REALTIME, not monotonic), so timestamps from different hook invocations are directly comparable.

## Layer 2 — `agent-bridge.py`

Long-running asyncio Unix-socket server. Maintains:

| Field | Purpose |
|-------|---------|
| `_clients[nvim_pid][buf]` | Registered orchestrator instances (keyed by Neovim PID and buffer). |
| `_activities[agent_id]` | Current state per agent, plus `event_ts_ns` for ordering. |
| `_activity_history[agent_id]` | Ring buffer of last 20 transitions. |
| `_subagent_depth[agent_id]` | SubagentStart/Stop pairing counter per parent agent. |
| `_warned_stuck` | Agents we've already logged a stuck warning for. |

### Out-of-order detection

When an activity message arrives with `event_ts_ns < prev_event_ts_ns`, the bridge logs:

```
activity OUT-OF-ORDER | 84840_6 event=Stop state=idle arrived 47ms after newer event (prev_state=working)
```

The message is **still applied**. Dropping it might be correct in some cases (e.g., a late `PreToolUse` arriving after `Stop`) but wrong in others (e.g., a late `Stop` arriving after `PreToolUse` — the Stop is the truth). We log first, decide later. If the symptom correlates with these warnings, we have a clear next step: change `handle_message` to ignore activity messages whose `event_ts_ns` is older than the current entry's.

### Recap detection (SubagentStart/Stop pairing)

Claude Code's recap is implemented as a **post-Stop background subagent** that emits `SubagentStop` once its summary text is generated. Because the parent agent's `Stop` already fired before the recap subagent was spawned, the bridge would receive a `SubagentStop` event for an agent_id that is no longer in `_activities` — and would naively re-create the entry as `thinking`, leaving the bar stuck.

The bridge defends against this by tracking a per-parent-agent depth counter, `_subagent_depth[agent_id]`:

| Event | Action |
|-------|--------|
| `SubagentStart` | Increment counter |
| `SubagentStop`, counter > 0 | Decrement counter, apply state normally |
| `SubagentStop`, counter == 0 | **Drop the message** — log `RECAP DETECTED` |
| `Stop` (parent) | Reset counter to 0 (clears any in-flight Tasks; future SubagentStop for this agent is by definition orphan) |

This is a **deterministic** classifier — no time thresholds, no heuristics. A Task subagent that runs for 10 minutes during a parent turn pairs correctly; a recap subagent that fires hours after parent Stop is correctly dropped.

The `RECAP DETECTED` log line appears once per recap event, with the prior state included for context. Counts of these events over time give us empirical confirmation that recap is the cause.

The depth map is exposed in the SIGUSR1 dump under `subagent_depth` so a stuck-state postmortem can verify the counter was in the expected range when the symptom occurred.

### Stuck-working watchdog

Every 5 seconds, the bridge inspects all activity entries. For any agent that has been in `working` for ≥ 120s without a transition, it logs ONCE:

```
STUCK WORKING | 84840_6 in 'working' for 137s (last 5: thinking(PostToolUse) | working(PreToolUse) | thinking(PostToolUse) | working(PreToolUse) | working(PreToolUse))
```

The history tail in the warning is the smoking gun for diagnosing the cause — you can see the exact hook sequence that put the agent into the stuck state.

The warning is purely observational. The orchestrator's `quiet_bufs` liveness path (terminal silent for 60s) is the actual recovery mechanism; this watchdog just tells us when recovery should have happened but didn't.

### Claude CLI reconciliation (cancellation catch-all, added 2026-06-11)

Claude Code fires **no hook at all when the user cancels a turn with Esc** — the Stop hook is officially documented as "does not run if the stoppage occurred due to a user interrupt" (feature requests anthropics/claude-code#9516 / #45289 remain open). A canceled agent therefore stays `working`/`thinking` forever from the hooks' point of view. Research notes: `.claude/memory/project_claude_cancel_detection.md`.

The bridge closes this gap by polling ground truth. Every reaper tick (5s), `reconcile_claude_sessions()` looks for local Claude agents that have been in a busy state with no hook traffic for ≥ `CLAUDE_RECONCILE_AFTER_SECONDS` (15s). If any exist (and the CLI hasn't been invoked within `CLAUDE_RECONCILE_MIN_INTERVAL`), it runs `claude agents --json` (CLI v2.1.145+) and joins on the `session_id` the hook script now passes through in every activity message. An agent is force-cleared to idle **only** when the CLI explicitly reports its session as `status: "idle"` — missing sessions and absent status fields are left alone (process death belongs to the orphan reaper / liveness paths). Cleared agents get a `(cli-reconcile)` entry in their history ring and a `RECONCILE |` log line.

Excluded from reconciliation: OpenCode agents (invisible to the claude CLI; their `session.idle` plugin event already handles cancel correctly) and remote SSH-tunneled agents (not in the local CLI output — these still rely on the timeout/liveness fallbacks).

Two faster, partial signals are also wired in the hook layer:
- `Notification` with the `idle_prompt` matcher (settings.json passes an `idle-notification` argv marker) → `idle`. Fires after Claude's idle threshold (~60s), so it's a delayed clear.
- `PostToolUseFailure` with `is_interrupt: true` → `idle`. The field is undocumented (unverified as of 2026-06-11); the hook logs `interrupt |` whenever it is actually observed so we can confirm the signal empirically.

### SIGUSR1 diagnostic dump

```bash
pkill -USR1 -f agent-bridge.py
cat ~/.local/state/symmetria/agent-bridge-diagnostic.json | jq
```

If the file is not updated (or does not exist), check the debug log for a
`write_diagnostic_dump: failed` line — the most common cause is the state
directory not existing yet (`mkdir -p ~/.local/state/symmetria` to create it).

The dump includes every client, every activity entry with `stuck_for_seconds`, every history ring, and the warned-stuck set. Written atomically (`.tmp` + rename) so a reader can never see a half-written file.

## Layer 3 — QML `AgentService.qml`

The QML side already logs every state diff (`state | <id> prev→curr`). Two additions:

### `_stateEnteredAt` per-agent timestamps

Each agent's wall-clock entry time into its current state. Used by both the stuck watchdog and the diagnostic snapshot's `state_age_ms`.

We deliberately do NOT delete entries when an agent disappears: V8 de-opts a hashmap whose keys are deleted (CLAUDE.md project standard P0). Leaving stale entries is harmless because (a) they're overwritten on next sighting and (b) the key space is bounded by all `agent_id`s seen this shell session.

### Stuck watchdog Timer

Runs every 30s. For any agent in `working` for ≥ 120s, logs once:

```
STUCK WORKING | 84840_6 project=symmetria tool=Running stuck_for=137s
```

Cleared on the agent's next state transition.

### `agentbar diagnose` IPC

```bash
symmetria shell agentbar diagnose
```

Returns a JSON snapshot with per-agent state/tool/age/warned_stuck flags. Use it to compare QML's view against the bridge's SIGUSR1 dump.

```bash
symmetria shell agentbar reportStuck 84840_6
```

Logs a structured `report-stuck` and `report-stuck-snap` line — useful as a "user pressed the panic button" marker so we can grep for the moments the user noticed the bug.

## Common patterns and what they mean

### Pattern 1 — Stop never reached the bridge

```
[py:hook] hook | agent=X event=PreToolUse state=working
[py:hook] hook | agent=X event=PostToolUse state=thinking
[py:hook] hook | agent=X event=PreToolUse state=working
... (no Stop ever logged)
[py:bridge] STUCK WORKING | X in 'working' for 137s
```

Cause: no `Stop` ever reached the bridge. The **most common reason is user cancellation** — Claude Code deliberately fires no hook on Esc (see "Claude CLI reconciliation" above, which now recovers this case within ~15–25s). Rarer reasons:
- `SYMMETRIA_AGENT_ID` was unset at Stop time (orchestrator unset it during teardown).
- Claude Code crashed before firing Stop.
- The hook process was killed before reaching `sock.sendall`.

If this pattern appears WITHOUT a subsequent `RECONCILE |` line clearing it, the reconciler itself failed — check for `reconcile |` warnings (CLI missing, timeout, parse failure) in the bridge log.

### Pattern 0 — Recap subagent (FIXED 2026-04-25)

```
[py:hook] hook | agent=X event=Stop state=idle
... (silence for 10s–24m) ...
[py:hook] hook | agent=X event=SubagentStop state=thinking
[py:bridge] RECAP DETECTED | X SubagentStop without preceding SubagentStart — dropping (was state=idle)
```

This was the root cause of the long-standing "stuck on working/thinking after recap" symptom. Claude Code spawns a post-Stop background subagent to generate the conversation recap text; when that subagent finishes, it fires SubagentStop for the parent agent_id long after the parent's Stop already cleared the slot. Without the SubagentStart/Stop pairing rule, the bridge would re-create the entry as `thinking` and leave it stuck (no Stop ever follows).

If `RECAP DETECTED` is ever absent from the bridge log around a stuck-state symptom, the cause is something else — investigate Pattern 1, 2, or 3.

### Pattern 2 — Stop arrived but raced with PreToolUse

```
[py:hook] hook | agent=X event=PreToolUse state=working ts_ns=...
[py:hook] hook | agent=X event=Stop state=idle ts_ns=...
[py:bridge] activity | X working→idle event=Stop
[py:bridge] activity OUT-OF-ORDER | X event=PreToolUse state=working arrived 12ms after newer event
[py:bridge] activity | X idle→working event=PreToolUse
```

Cause: async hooks raced over the socket; Stop won, then a stale PreToolUse arrived 12ms later and re-set state to working. Bridge's current behavior is to apply both — the late PreToolUse wins.

Fix direction: in `handle_message`, when `state == "working"` and `event_ts_ns < self._activities.get(agent_id, {}).get('event_ts_ns', 0)`, drop the message instead of applying it.

### Pattern 3 — Bridge has idle, QML shows working

The bridge's diagnostic dump shows the agent missing from `_activities` (i.e., it correctly cleared on Stop), but `symmetria shell agentbar diagnose` still has the agent with `state: "working"`. This is a QML-side bug — typically a missed SplitParser line or a binding that didn't refresh.

The QML `STUCK WORKING` log line proves QML is the source of truth for the displayed value.

### Pattern 4 — Agent for project X never appears in the bar (FIXED 2026-04-26)

Symptom: an entire project's agent group is missing from the agent bar even though `nvim` is running in that project's directory and the orchestrator is sending events. The bridge log around bridge-startup shows:

```
[py:bridge] CLIENT identified: nvim_pid=84840
[py:bridge] CLIENT identified: nvim_pid=84840   ← second connection from same pid, ~1ms later
[py:bridge] CLIENT EOF: nvim_pid=84840          ← one of them closes
[py:bridge] remove_client: dropping pid=84840 (4 instances)   ← DESTROYS state for the still-alive sibling
... (forever after) ...
[py:bridge]   updated: unknown buf=10 for pid=84840 (known: [])
[py:bridge]   focus: unknown pid=84840 (not registered)
```

Cause: during bridge restart, two parallel orchestrator connections briefly overlap (one from the bridge's `solicit_neovim_instances` RPC, one from the orchestrator's own auto-reconnect). Both register the client. When ONE closes, the bridge's `handle_client` finally-block called `remove_client(nvim_pid)` unconditionally — which wiped state for the still-alive sibling. All subsequent messages on that surviving connection arrived into a "client never registered" state and fell through silently.

Fix: per-pid connection counter (`_conn_count`). `handle_client` increments on identification and decrements on close; `remove_client` only fires when the count reaches zero (true last-connection-closed). Combined with the desync safety net described next.

### Self-healing desync recovery

A general defense against any cause of orchestrator-bridge state desync:

When a state-mutation message (`updated`/`removed`/`focus`/`liveness`/`added`) arrives for an `nvim_pid` that is NOT in `_clients`, the bridge logs:

```
DESYNC | pid=84840 sent message without prior hello/sync — soliciting reconnect
```

…and triggers a one-shot `solicit_neovim_instance` RPC asking the orchestrator to re-send `hello`+`sync`. The throttle is 10 seconds per pid so an unregistered orchestrator sending `liveness` every minute (or `updated` every second) doesn't spam the RPC.

This catches not only the parallel-connection race but also any future cause of desync we haven't yet diagnosed: orchestrator restart while the bridge is alive, missed-RPC at bridge startup, transient socket failures, etc. If `DESYNC` ever appears in the log without a corresponding successful resolicit log line, the orchestrator's `bridge.reconnect()` itself is broken — that's a separate bug to investigate.

## Future work

- **Automatic out-of-order suppression** once we have data confirming pattern 2 is the root cause. Implementation sketch: drop activity messages whose `event_ts_ns` is older than the current entry's, EXCEPT when the new state is `idle`/`offline` (terminal states should always be applied — late truth beats stale lie).
- **Bridge → orchestrator force-clear IPC** so the QML `reportStuck` IPC can actually clear the state instead of just logging the user's complaint.
- **Per-agent state-transition graph in the dashboard** rendering the last N transitions visually. The data is already in `_activity_history`; only the dashboard UI is missing.
