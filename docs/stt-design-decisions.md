# STT Design Decisions

Design rationale for the Speech-to-Text pipeline that isn't obvious from reading `SttService.qml`. These decisions were born from real bugs.

## Target Locking at Start-Time

**Principle:** Both the terminal window target and agent target are captured exactly once at `start()` and carried immutably through the entire pipeline: recording → transcription → clipboard → injection. Never re-resolve at stop-time or delivery time.

**Why:** The user sees a highlighted icon during recording that indicates which window will receive the transcription. If the target is re-resolved later (when focus may have changed), the delivery target won't match the visual indicator — causing text to go to the wrong window.

**Implementation:** `_captureTargetWindow()` saves Hyprland address + class + PID. `_resolveAgentTarget()` resolves Neovim socket + buf via `activeAgentForTerminal`. Both run at `start()` and their results are never overwritten.

## Identity-Unstable Lookups in Async Pipelines

`AgentService.activeAgentForTerminal(pid)` resolves identity through *current state* — it calls `representativeAgent()` which returns `agents.find(a => a.active) ?? agents[0]`. When multiple agents share a terminal PID (same Neovim instance), calling this function at different times returns different agents depending on which one is currently focused.

**Rule:** Never call `activeAgentForTerminal()` after `start()`. The function `_refreshAgentTarget()` exists but must NOT be called — it would re-resolve and potentially change the delivery target.

## Historical Bugs (Now Fixed)

These document WHY certain code patterns exist:

1. **clipboardProcess.onExited re-resolution** — Had a "refresh" block that re-resolved the agent target after transcription completed. Fixed by removing it entirely.

2. **on_ActiveDeliveryChoiceChanged re-resolution** — Re-resolved via `activeAgentForTerminal()` when the user changed delivery mode during recording. Fixed by using `_targetNvimActiveBuf` directly.

3. **Stop-time _refreshAgentTarget()** — Could change the delivery target after the user already saw the start-time icon during recording. Removed from `stop()` to ensure visual always matches delivery.

4. **Silent last_active_buf fallback** — In the orchestrator's `stt_inject()`, when an explicit `target_buf` was passed but invalid, it silently fell back to `last_active_buf` — delivering to the wrong agent. Fixed to return `target_buf_invalid` error instead.

## Delivery Pipeline Timing

- **50ms clipboard propagation delay** — Between `wl-copy` and `sendshortcut`. Ensures the Wayland compositor has received the clipboard data before the paste shortcut fires.

- **150ms auto-submit delay** — Between paste and Enter in submit mode. Gives the application time to process clipboard content before receiving the Enter key.

- **500ms restart delay** — Between cancel and re-start in `restart()`. Ensures all processes from the cancelled session are fully terminated.

## Design Principles

- **No focus change** — `sendshortcut` with address targeting pastes without stealing focus from the user's current window.
- **Best-effort injection** — Injection failure is non-fatal; clipboard always has the text as fallback.
- **Terminal detection** — Ghostty, Alacritty, Kitty, Foot, WezTerm, Warp, Konsole use `Ctrl+Shift+V`; all others use `Ctrl+V`.
- **Retry preserves target** — `retry()` does NOT clear the captured window, so re-transcription injects to the same target.
- **Explicit target_buf** — When QML passes a specific `target_buf`, the script MUST find it or fail. No silent fallback.
