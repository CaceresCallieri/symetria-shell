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

## Model Selection & Long-Audio Truncation

**The gotcha:** `gpt-4o-transcribe` (and `gpt-4o-mini-transcribe`) silently truncate long transcriptions. They are LLMs that emit the transcript as *output tokens*, and they have a bounded output ceiling (~2000 tokens ≈ ~9,000 characters ≈ ~10 minutes of speech). Past that, the model **stops generating mid-transcript and still returns HTTP 200** — so the failure is invisible to the pipeline, which only inspects the status code. A real incident: an 18-minute recording came back as 9,006 characters (the tail third was missing), reported as a success, and the source audio was deleted before anyone noticed.

**Why whisper-1 doesn't have this problem:** `whisper-1` chunks audio internally into 30-second windows and stitches the results, so it has no output-token ceiling (limit is the 25 MB / ~25 min file size, not transcript length). It will not truncate.

**The trade-off (why we didn't just switch globally):**

| | `gpt-4o-transcribe` | `whisper-1` |
|---|---|---|
| Prompt handling | LLM — *follows* the verbatim + paragraph-formatting instructions | Treats `prompt` as a ~224-token style/vocab **prime**, NOT instructions — ignores formatting, can bias output toward prompt words |
| Long audio | Silently truncates (~10 min) | Complete, no truncation |
| Accuracy / mixed EN-ES | Generally better | Good, slightly older |

So gpt-4o-transcribe is the better model for the common case (short dictation: more accurate, adds paragraph breaks), and whisper-1 only wins on length.

**The fix: duration-based auto-selection.** `SttJob._startTranscription()` reads `elapsedSeconds` (the full recording duration, finalized at stop) and routes recordings longer than `Config.stt.longAudioThresholdSec` (default 420 s, safely under the ~10-min truncation point) to `Config.stt.longAudioModel` (default `whisper-1`). Short recordings keep `Config.stt.model` (gpt-4o-transcribe). Set `longAudioThresholdSec` to 0 to disable routing; set `model` itself to `whisper-1` for a blanket switch.

- **Model-aware prompt** — `stt-transcribe.sh` branches the `prompt` form on `$MODEL`: full verbatim/paragraph block for gpt-4o, a short language hint for `whisper*`. Sending the long directive block to whisper is inert at best and can pollute the output.
- **Known limitation** — Long takes routed to whisper-1 lose paragraph formatting (whisper ignores the instruction). *Complete-but-unformatted beats truncated-with-paragraphs.* A future client-side chunking path could keep gpt-4o quality on long audio; see `stt-future-work.md`.

## Successful-Recording Retention (Safety Net)

Because a truncated transcription reports success, the old delete-on-success policy (`_cleanupTempFiles()` on the tmpfs working copy) made the source audio **unrecoverable** the instant it went wrong — and tmpfs (`/run/user/$UID/...`) has no carve-able inodes, so undelete tools can't help.

**The net:** when `Config.stt.cache.retainSuccessHours > 0` (default 24), `SttJob._persistHistory()` copies the source audio plus a transcript sidecar (model used, `durationSec`, `charCount`, delivered text) to the on-disk dir `${Paths.state}/stt/history/` *before* the tmpfs copy is cleaned. Disk (not tmpfs) is required so the window survives logout/reboot. Pruned by age (`retainSuccessHours`, swept at startup *and* after each success) plus a count cap (`maxSuccessEntries`, default 50). The WAV is written via temp-name + atomic `mv` so a job destroyed mid-copy can't leave a truncated file that looks complete.

This is distinct from `_persistRecovery()` / `${Paths.state}/stt/recoverable/`, which fires only on *final failure* for retry-after-restart and carries error fields, not the transcript.

## Design Principles

- **No focus change** — `sendshortcut` with address targeting pastes without stealing focus from the user's current window.
- **Best-effort injection** — Injection failure is non-fatal; clipboard always has the text as fallback.
- **Terminal detection** — Ghostty, Alacritty, Kitty, Foot, WezTerm, Warp, Konsole use `Ctrl+Shift+V`; all others use `Ctrl+V`.
- **Retry preserves target** — `retry()` does NOT clear the captured window, so re-transcription injects to the same target.
- **Explicit target_buf** — When QML passes a specific `target_buf`, the script MUST find it or fail. No silent fallback.
