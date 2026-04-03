# Investigation: stt-wrong-agent-delivery

**Started**: 2026-03-12
**Status**: Active

---

## Pass 1

**Timestamp**: 2026-03-12
**Status**: testing-fix

### Findings

- User has `deliveryMode: "ask"` in `~/.config/symmetria/shell.json`
- All 11 Ghostty windows have UNIQUE PIDs (verified via `hyprctl clients -j`) — Ghostty spawns separate processes per window
- Bridge's `_resolve_terminal_pid()` correctly maps `nvim_pid → terminal_pid` matching Hyprland window PIDs (verified with 7 running Neovim instances)
- `_captureTargetWindow()` at `SttService.qml:389` had a stale doc comment: "Called at both start() and stop()" — but `stop()` never called it
- `_resolveAgentTarget()` at `SttService.qml:415` was only called from `start()` — agent buf captured once, never refreshed
- The bridge pipeline has 50ms coalescing (`agent-bridge.py:148`) + 100ms QML throttle (`AgentService.qml:442`), creating up to 150ms staleness for the `active` flag
- `representativeAgent()` at `AgentService.qml:140-143` uses `agents.find(a => a.active) ?? agents[0]` — when multiple agents share a terminal, a stale `active` flag picks the wrong agent
- `stt_inject()` in `orchestrator/init.lua:415-446` had a silent fallback: when explicit `target_buf` was invalid, it fell through to `last_active_buf` (Priority 1), which tracks real-time focus — silently delivering to a different agent

### Hypotheses

| # | Hypothesis | Confidence | Evidence |
|---|-----------|------------|----------|
| 1 | Stale `active` flag at start-time captures wrong agent buf | HIGH | 150ms throttle window confirmed; user has multiple agents in same Neovim |
| 2 | Silent `last_active_buf` fallback in stt_inject delivers to wrong agent | MED | Fallback exists but requires target_buf to be invalid at delivery time |

### Eliminated

- **Ghostty single-process PID collision**: Eliminated because `hyprctl clients -j` shows each Ghostty window has a unique PID (11 windows, 11 different PIDs). The bridge's `terminal_pid` correctly matches Hyprland's window PIDs.
- **Socket2 vs IPC race condition**: Eliminated because Hyprland processes keybinds sequentially and the `qs` CLI IPC takes 50-200ms to spawn, giving socket2 events time to propagate
- **Type mismatch in `activeAgentForTerminal`**: Eliminated because both `_targetWindowPid` (QML int) and `a.terminal_pid` (JSON-parsed number) are coerced to the same numeric type by QML's property system
- **Re-resolution at delivery time**: Eliminated because no code path calls `_resolveAgentTarget()` or `activeAgentForTerminal()` after start-time — the captured values are stable through the async pipeline
- **Buffer number reuse**: Eliminated because Neovim buffer numbers are monotonically increasing within a session

### Code Paths

> **Note:** The stop-time `_refreshAgentTarget()` call described in rows 2-3 was reverted in Pass 2.

| File | Lines | Role |
|------|-------|------|
| `services/SttService.qml` | 197-252 | `start()` — captures window + resolves agent at start-time |
| `services/SttService.qml` | 254-284 | `stop()` — NOW calls `_refreshAgentTarget()` before submitting |
| `services/SttService.qml` | 391-415 | `_refreshAgentTarget()` — NEW: re-resolves agent within same terminal at stop-time |
| `services/SttService.qml` | 417-448 | `_captureTargetWindow()` + `_resolveAgentTarget()` — start-time capture |
| `services/SttService.qml` | 827-870 | `clipboardProcess.onExited` — delivery chain using captured targets |
| `services/AgentService.qml` | 140-143 | `representativeAgent()` — picks agent by `active` flag |
| `services/AgentService.qml` | 294-299 | `activeAgentForTerminal()` — filters agents by terminal PID |
| `scripts/stt-inject.sh` | 82-155 | `_try_rpc()` + `try_neovim_inject()` — Neovim RPC injection |
| `~/projects/orchestrator.nvim/lua/orchestrator/init.lua` | 394-460 | `stt_inject()` — target resolution priority chain |
| `~/projects/orchestrator.nvim/lua/orchestrator/init.lua` | 653-663 | BufEnter autocmd — updates `last_active_buf` real-time |
| `scripts/agent-bridge.py` | 96-134 | `_emit()` + `_schedule_emit()` — 50ms coalesced stdout emission |

### Fix Applied

**SttService.qml:**
- Added `_refreshAgentTarget()` function (lines 391-415) — re-resolves agent within same terminal at stop-time
- `stop()` now calls `_refreshAgentTarget()` before submitting
- Logs `agent-retarget` when the agent changes between start and stop

**orchestrator/init.lua:**
- When `target_buf > 0` is explicitly passed but buf is invalid/not found, returns `{ok: false, error: "target_buf_invalid"}` instead of falling through to `last_active_buf`
- Heuristic fallbacks (last_active_buf, most recently spawned) only used when NO explicit target was provided

**CLAUDE.md:**
- Updated Window Injection Flow, design decisions, and Identity-Unstable Lookups documentation

### Next Steps

- [ ] Test with two agents in same Neovim: start STT on Agent A, keep focus on A, press stop — verify text goes to Agent A and correct icon was highlighted
- [ ] Test with single agent (regression): ensure normal STT still works
- [ ] Test `target_buf_invalid` error path: if an agent closes during recording, verify the error is surfaced (not silently delivered to wrong agent)
- [ ] Verify agent icon ordering in dashboard matches buffer order in Neovim

### Open Questions

- Agent ordering: the bridge sorts by `(project, "{nvim_pid}_{buf}")` — is this intuitive to the user, or should ordering use a different key (e.g., spawn time)?

---

## Pass 2

**Timestamp**: 2026-03-12
**Status**: testing-fix

### Findings

- User tested Pass 1 fix and found: transcription went to correct agent, but the **wrong icon** was highlighted in the dashboard during recording
- Root cause: `_refreshAgentTarget()` at stop-time changed the delivery target AFTER the user saw the start-time icon during recording → visual/delivery mismatch
- The stop-time refresh was solving a theoretical 150ms-staleness problem, but in practice the user is focused on an agent for seconds before pressing STT — the `active` flag has always caught up by then
- The stop-time refresh could actually CHANGE the target unexpectedly if focus shifted during recording

### Fix Applied

**SttService.qml:**
- Removed `_refreshAgentTarget()` call from `stop()` — target is now fully locked at start-time
- Both visual (icon highlight) and delivery (injection target) use the same start-time captured values
- `_refreshAgentTarget()` function retained but unused (reserved for potential future retarget command)

**CLAUDE.md:**
- Updated design decision: "Everything locked at start-time"
- Updated Window Injection Flow steps to remove stop-time refresh
- Added historical bug #3 (stop-time refresh causing visual/delivery mismatch)
- Updated Identity-Unstable Lookups rule: target resolved exactly once at `start()`

### Next Steps

- [x] Test with two agents in same Neovim — **FAILED**: both agents `active: false`, wrong agent selected
- [ ] Test single agent regression
- [ ] Verify agent ordering in dashboard

---

## Pass 3

**Timestamp**: 2026-03-12
**Status**: root-cause-identified

### Findings

- Added diagnostic logging to `_resolveAgentTarget()`, `representativeAgent()`, and `agent-bridge.py:added` handler
- User reproduced the bug: two agents in Vigilia project (nvim_pid=247988, buf=3 and buf=6), user focused on buf=6, STT targeted buf=3
- **Diagnostic output confirmed the root cause** — BOTH agents have `active: false` permanently:
  ```
  [STT:DIAG]   agent[0]: id=247988_3 buf=3 active=false project=vigilia activity=starting
  [STT:DIAG]   agent[1]: id=247988_6 buf=6 active=false project=vigilia activity=starting
  [AgentService:DIAG] representativeAgent: count=2 flags=[247988_3:false, 247988_6:false] found=NONE result=247988_3
  ```
- With both agents `active: false`, `agents.find(a => a.active)` returns `undefined`, fallback `?? agents[0]` always picks the first agent by sort order (lowest buf number = buf=3)
- The `active` flag is NEVER set to `true` for either agent because the initial BufEnter fires BEFORE `instances.register_spawned()` is called

### Root Cause: BufEnter/Registration Race in orchestrator.nvim

**The spawn sequence has a critical ordering bug:**

1. `vim.fn.termopen()` creates terminal buffer → Neovim displays it → **BufEnter fires**
2. BufEnter callback at `init.lua:663-673`: `instances.get_by_buf(current_buf)` → returns **nil** (not registered yet) → `notify_focus()` is **NOT called** → `last_active_buf` is **NOT updated**
3. `instances.register_spawned()` at `instances.lua:56-96`: inserts instance, then calls `bridge_module.notify_spawn(instance)` → `build_instance_data()` at `bridge.lua:171-183` sets `active = (inst.buf == state.state.last_active_buf)` → `last_active_buf` is stale → **`active: false`**
4. No subsequent BufEnter fires (user is already on this buffer) → `active` stays **permanently false**

**Consequence:** `representativeAgent()` fallback `?? agents[0]` always selects the first agent by sort order, regardless of which agent the user is actually focused on. This explains why:
- Both agents show `active: false` in every `representativeAgent` call
- STT always targets the agent with the lowest buf number
- The bug is 100% reproducible (not a race condition — it's a deterministic ordering bug)

### Hypotheses

| # | Hypothesis | Confidence | Evidence |
|---|-----------|------------|----------|
| 1 | BufEnter fires before `instances.register_spawned()` → initial focus event lost → `active` permanently false | **CONFIRMED** | Diagnostic logs show BOTH agents `active: false` across ALL representativeAgent calls; code path analysis confirms BufEnter precedes registration |

### Eliminated

- **150ms throttle staleness (Pass 1 hypothesis #1)**: Eliminated as the PRIMARY cause. The throttle creates a brief window, but the real issue is that `active` is NEVER set to true in the first place. The throttle is irrelevant when the initial focus event is lost entirely.
- **Stop-time refresh causing visual mismatch (Pass 2)**: This was a real secondary issue (removed the stop-time refresh), but not the root cause. Even with the refresh, both agents had `active: false`, so the same wrong agent would be selected.

### Code Paths

| File | Lines | Role |
|------|-------|------|
| `~/projects/orchestrator.nvim/lua/orchestrator/instances.lua` | 56-96 | `register_spawned()` — registers instance AFTER terminal buffer is created and focused |
| `~/projects/orchestrator.nvim/lua/orchestrator/bridge.lua` | 171-183 | `build_instance_data()` — reads `state.state.last_active_buf` to set `active` flag |
| `~/projects/orchestrator.nvim/lua/orchestrator/bridge.lua` | 304-310 | `notify_spawn()` — sends `added` message with stale `active` flag |
| `~/projects/orchestrator.nvim/lua/orchestrator/bridge.lua` | 322-330 | `notify_focus()` — sends `focus` message (never called for initial spawn) |
| `~/projects/orchestrator.nvim/lua/orchestrator/init.lua` | 663-673 | BufEnter autocmd — only calls `notify_focus` if `instances.get_by_buf()` returns non-nil |
| `scripts/agent-bridge.py` | 248-256 | `added` handler — stores instance data including stale `active` flag, does NOT update other agents' flags |
| `scripts/agent-bridge.py` | 282-293 | `focus` handler — correctly sets `active` for all bufs (but never receives the initial focus) |
| `services/AgentService.qml` | 140-150 | `representativeAgent()` — `agents.find(a => a.active) ?? agents[0]` fallback always picks first agent |

### Errors & Symptoms

```
[STT:DIAG] _resolveAgentTarget | terminalPid: 247506 | totalAgents: 9 | matchingPid: 2
[STT:DIAG]   agent[0]: id=247988_3 buf=3 active=false project=vigilia activity=starting
[STT:DIAG]   agent[1]: id=247988_6 buf=6 active=false project=vigilia activity=starting
[AgentService:DIAG] representativeAgent: count=2 flags=[247988_3:false, 247988_6:false] found=NONE result=247988_3
[STT:DIAG] SELECTED: id=247988_3 buf=3 active=false
```

Reproduction: Open Neovim, spawn two Claude agents in the same project (`:Claude` twice). Without navigating away from agent #2 and back, press STT keybind → agent #1 is always selected.

### Proposed Fix (NOT YET IMPLEMENTED)

**In `instances.lua:register_spawned()`** — after inserting the instance and calling `notify_spawn`, check if the newly registered buffer is the current buffer. If so, update `last_active_buf` and call `notify_focus()`:

```lua
table.insert(state.state.claude_instances, instance)

-- ... existing status_bar and bridge_module.notify_spawn code ...

-- Fix: Emit focus for the current buffer now that it's registered.
-- BufEnter fires BEFORE registration, so the initial focus event is lost.
-- This ensures the `active` flag is correct from the moment the agent appears.
if buf == vim.api.nvim_get_current_buf() then
    state.state.last_active_buf = buf
    if bridge_module then
        bridge_module.notify_focus(buf)
    end
end
```

**Also fix `build_instance_data()` in `bridge.lua`** — since `notify_spawn()` also calls `build_instance_data()` which reads `last_active_buf`, moving the `last_active_buf` update BEFORE `notify_spawn()` would make the `active` flag correct in the `added` message too. This eliminates the brief window where the bridge has stale data.

### Next Steps

- [x] Implement the fix in `~/projects/orchestrator.nvim/lua/orchestrator/instances.lua:register_spawned()` — add `last_active_buf` update + `notify_focus()` after registration
- [x] Reorder in `register_spawned()`: update `last_active_buf` BEFORE `notify_spawn()` so `build_instance_data()` gets correct `active` flag in the `added` message
- [x] Remove `[STT:DIAG]` / `[AgentService:DIAG]` temporary investigation dumps from `SttService.qml`, `AgentService.qml`, and `agent-bridge.py` (permanent `[STT:D##]` trace logs retained)
- [ ] Test: spawn two agents in same Neovim → verify both get correct `active` flag immediately
- [ ] Test: STT on agent #2 → verify correct icon + correct delivery
- [ ] Test single-agent regression

### Open Questions

- ~~Should `register_spawned()` unconditionally set `last_active_buf = buf`?~~ **Resolved:** Uses `vim.api.nvim_get_current_buf()` check — safe for potential background spawn paths
