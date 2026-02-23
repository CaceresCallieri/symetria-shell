# PRD: Symmetria Native Speech-to-Text System

> **Status:** Draft
> **Author:** Discussion between user and Claude Code
> **Date:** 2026-02-20
> **Related:** [RFC Discussion #24](https://github.com/CaceresCallieri/symetria-shell/discussions/24), `docs/hyprwhspr-integration.md`

## 1. Overview

### Problem Statement

The current HyprWhspr integration works but has fundamental architectural limitations:

1. **Dual UI problem** — HyprWhspr renders its own GTK4 visualizer alongside Symmetria's QML drawer, causing visual duplication with no way to run headless
2. **File-based IPC fragility** — State files, inotifywait, and FIFO protocol introduce race conditions, stale data, and variable update rates
3. **Limited extensibility** — Features like transcription queuing, smart text delivery, and recording cache are impossible to build on top of an external daemon
4. **Dependency burden** — Python runtime (~100MB), GTK4, inotify-tools, systemd service management

### Solution

Build a **Symmetria-native STT system** that owns the entire pipeline: audio capture, transcription API calls, text delivery, and state management. This eliminates HyprWhspr as a dependency while reusing the existing UI layer (drawer, visualizer, control buttons) that was built during the Proposal A orchestrator phase.

### Guiding Principles

- **Own the pipeline** — No external daemons; Symmetria manages all subprocesses directly
- **Cloud-first, local-later** — Start with OpenAI GPT-4o Transcribe; add local/alternative backends later
- **Reuse existing UI** — The 641-line Content.qml visualizer and drawer system survive mostly unchanged
- **Design for queuing** — Architecture must support concurrent transcription jobs from day one
- **Graceful degradation** — Network errors, API failures, and edge cases must never lose user audio

---

## 2. Architecture

### High-Level Pipeline

```
┌────────────────────┐     IPC call          ┌──────────────────────────┐
│  Hyprland Keybind  │ ───────────────────── │  Symmetria IPC Handler   │
│  (Super+Alt+D)     │  "stt toggle en"      │  (existing pattern)      │
└────────────────────┘                       └──────────┬───────────────┘
                                                        │
                                                        ▼
                                             ┌──────────────────────────┐
                                             │  SttService.qml          │
                                             │  (Singleton)             │
                                             │                          │
                                             │  • State machine         │
                                             │  • Audio capture mgmt    │
                                             │  • Audio level (native)  │
                                             │  • API client            │
                                             │  • Job queue (future)    │
                                             └─────┬──────────┬─────────┘
                                                   │          │
                                          capture  │          │ transcribe
                                                   ▼          ▼
                                             ┌──────────┐ ┌──────────────┐
                                             │ pw-record │ │ curl / helper│
                                             │ (Process) │ │ → OpenAI API │
                                             └──────────┘ └──────┬───────┘
                                                                 │
                                                                 ▼
                                                          ┌──────────────┐
                                                          │ Text Delivery│
                                                          │ (clipboard / │
                                                          │  inject)     │
                                                          └──────────────┘
```

### Component Inventory

| Component | Status | Notes |
|-----------|--------|-------|
| **SttService.qml** | New (replaces HyprWhsprService.qml) | Core service singleton |
| **Stt.qml** | Rename from HyprWhspr.qml | IPC handler + visibility |
| **Content.qml** | Modify | Same visualizer, new service bindings |
| **Wrapper.qml** | Reuse | Unchanged animation wrapper |
| **SttBackground.qml** | Rename from HyprWhsprBackground.qml | Trivial rename |
| **SttConfig.qml** | New (replaces HyprWhsprConfig.qml) | Extended config |
| **Audio level monitor** | New | Shell pipeline subprocess |
| **API client** | New | curl-based transcription |
| **Text delivery** | New (future) | Smart injection system |

---

## 3. MVP Scope (v1.0)

### 3.1 Audio Capture

**Tool:** `pw-record` (PipeWire native, no external dependencies)

**Recording parameters:**
```bash
pw-record --target=0 --format=s16 --rate=16000 --channels=1 <output_path>
```

- 16kHz mono signed 16-bit — Whisper's native format, minimizes file size
- Output format: WAV (for direct API upload) or OGG Opus (for compression)
- Storage: temporary files in `$XDG_RUNTIME_DIR/symmetria-stt/` or `/tmp/symmetria-stt/`

**Process management:**
- Start: `recordProcess.running = true`
- Stop (save): Send `SIGINT` (signal 2) — pw-record finalizes WAV header gracefully
- Cancel (discard): Send `SIGKILL` (signal 9) + delete temp file

**Pause/Resume strategy: Stop-and-restart (Option B)**
- Pause: `SIGINT` current pw-record → saves segment file (e.g., `segment_001.wav`)
- Resume: Spawn new pw-record → new segment file (`segment_002.wav`)
- Submit: Concatenate all segments (via `ffmpeg` or `sox`) into single file, upload
- This matches HyprWhspr's proven approach and naturally extends to long-form

### 3.2 Audio Level Monitoring

**Approach: Dual subprocess (Approach 1)**

A second `pw-record` process streams raw PCM to a shell pipeline that computes RMS audio level and outputs it to stdout at ~10Hz:

```bash
pw-record --target=0 --format=s16 --rate=16000 --channels=1 - 2>/dev/null | \
    od -An -td2 -w3200 | \
    awk '{
        sum = 0; n = 0;
        for (i = 1; i <= NF; i++) { sum += $i * $i; n++ }
        if (n > 0) printf "%.4f\n", sqrt(sum / n) / 32768
        fflush()
    }'
```

- PipeWire natively multiplexes multiple readers from same audio source — no quality impact
- Zero external dependencies (od + awk are coreutils)
- QML reads via `Process.onStdout` — no file I/O, no inotify, no polling timer
- Deterministic 10Hz update rate (3200 bytes = 100ms of 16kHz mono s16)

**Improvements over HyprWhspr approach:**

| Aspect | HyprWhspr | New approach |
|--------|-----------|-------------|
| Data transport | File on disk + inotifywait | stdout pipe |
| Update rate | Variable (daemon-controlled) | Fixed 10Hz |
| Failure detection | None (stale file) | Process exit |
| Race conditions | File read during write | Impossible (line-buffered) |
| Dependencies | inotify-tools | None |
| Latency | inotify delay + file read | ~1ms pipe read |

**Future consideration:** C++ PipeWire integration in the Symmetria plugin (`plugin/src/Symmetria/`) for zero-overhead audio level via QML property binding. To be evaluated once MVP is stable.

### 3.3 Transcription Backend

**Primary backend: OpenAI GPT-4o Transcribe**

```bash
curl -s -X POST https://api.openai.com/v1/audio/transcriptions \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: multipart/form-data" \
    -F file=@recording.wav \
    -F model=gpt-4o-transcribe \
    -F response_format=text \
    -F language=<lang_code>
```

**Specs:**
- Price: $0.006/min ($0.36/hr)
- Max file: 25MB (~25 min WAV at 16kHz mono, or ~2-3 hrs OGG Opus)
- Streaming: SSE support (future enhancement for live preview)
- Supported formats: wav, ogg, flac, mp3, m4a, webm

**API key management:**
- Read from environment variable `OPENAI_API_KEY`
- Optionally configurable in `shell.json` under `stt.apiKey` (with file permission warning)
- Future: integration with system keyring / secret service

**Error handling:**
- HTTP 401 → "Invalid API key" (check configuration)
- HTTP 429 → "Rate limit / quota exceeded" (try again later)
- HTTP 5xx → "API server error" (retry with exponential backoff)
- Timeout → "Connection timed out" (check network)
- Network error → "No network connection"

### 3.4 Text Delivery (MVP)

**MVP delivers to clipboard only (Mode A).**

After successful transcription:
1. Copy result text to system clipboard via `wl-copy`
2. Show success state in drawer with preview of transcribed text
3. User pastes manually wherever they want

This is the simplest, most reliable approach. Smart injection (Modes B/C) is a future enhancement.

### 3.5 State Machine

Reuses the proven state machine from HyprWhsprService with simplifications (no file-watching complexity):

```
idle
  ├─ start(lang) ─────────────────→ recording
  │                                    │
  │                     pause() ←──────┤──────→ stop()
  │                        │           │            │
  │                        ▼           │            ▼
  │                     paused         │       processing
  │                        │           │            │
  │           resume() ────┘           │     ┌──────┼──────┐
  │                                    │     ▼      ▼      ▼
  │           cancel() ←───────────────┤  success  error  timeout
  │              │                     │     │      │
  │              ▼                     │     │   retry()──→ processing
  │           idle ←───────────────────┘─────┘
  │
  └─ toggle(lang): start if idle, stop if recording/paused
```

**Key state properties exposed to UI:**

| Property | Type | Description |
|----------|------|-------------|
| `state` | string | idle/recording/paused/processing/error/success |
| `audioLevel` | real | 0.0-1.0 from level monitor subprocess |
| `elapsedSeconds` | real | Wall-clock recording time (pause-aware) |
| `language` | string | Current language code (en, es, etc.) |
| `active` | bool | Whether drawer should be visible |
| `errorDetail` | string | User-friendly error message |
| `errorHint` | string | Actionable recovery hint |
| `transcribedText` | string | Result text (for success state preview) |

### 3.6 IPC Interface

Same IPC target pattern, renamed from `hyprwhspr` to `stt`:

```bash
qs -c symmetria ipc call stt toggle en     # Toggle (start/stop)
qs -c symmetria ipc call stt start en      # Start recording
qs -c symmetria ipc call stt stop          # Submit for transcription
qs -c symmetria ipc call stt pause         # Pause/Resume toggle
qs -c symmetria ipc call stt cancel        # Cancel & discard
qs -c symmetria ipc call stt restart       # Cancel + re-start recording
qs -c symmetria ipc call stt retry         # Retry failed transcription
```

### 3.7 Configuration

```json
{
    "stt": {
        "enabled": true,
        "backend": "openai",
        "apiKey": "",
        "model": "gpt-4o-transcribe",
        "autoHideDelay": 1500,
        "processingTimeout": 120000,
        "deliveryMode": "clipboard",
        "recording": {
            "format": "wav",
            "sampleRate": 16000,
            "channels": 1
        },
        "cache": {
            "enabled": true,
            "maxEntries": 10,
            "deleteOnSuccess": true
        }
    }
}
```

### 3.8 Dependencies

**Added:**
- `pipewire` (pw-record) — already installed on any PipeWire system
- `curl` — already installed on virtually all Linux systems
- `wl-clipboard` (wl-copy) — already a Symmetria dependency

**Removed:**
- `hyprwhspr` (Python daemon)
- `inotify-tools` (inotifywait)
- Systemd service management for external daemon

**Optional (for pause/resume segment concatenation):**
- `ffmpeg` or `sox` — for joining audio segments

---

## 4. Future Features

### 4.1 Smart Text Delivery (Modes B & C)

Three delivery modes, configurable per-session or globally:

| Mode | Name | Behavior |
|------|------|----------|
| A | Clipboard | Copy to clipboard, no paste (MVP) |
| B | Window Inject | Inject into the window that was active at Submit time |
| C | Inject + Enter | Same as B, plus send Enter keypress after injection |

**Window Inject implementation** (based on Snippet Manager pattern):

```bash
# At submit time: capture target window
target_window=$(hyprctl activewindow -j)
target_address=$(echo "$target_window" | jq -r '.address')
target_class=$(echo "$target_window" | jq -r '.class')

# After transcription completes:
# 1. Backup clipboard
original=$(wl-paste 2>/dev/null)
# 2. Copy transcription
printf '%s' "$text" | wl-copy
# 3. Focus target window
hyprctl dispatch focuswindow "address:$target_address"
# 4. Detect paste shortcut (terminal vs GUI)
# 5. Send paste: hyprctl dispatch sendshortcut "$paste_shortcut"
# 6. Restore clipboard
printf '%s' "$original" | wl-copy
# 7. (Mode C) Send Enter: hyprctl dispatch sendshortcut ",Return,"
# 8. Return focus to user's current window
```

**Edge cases:**
- Target window closed → fall back to clipboard mode, notify user
- Target window minimized → restore it, paste, re-minimize
- User confirmation fallback → if silent injection not possible, show prompt: "Transcription ready. Inject into [window name]?" with OK/Cancel

**Terminal detection** (from Snippet Manager):
- Ghostty, Warp, Zed → `Ctrl+Shift+V`
- Everything else → `Ctrl+V`

**Claude Code special handling (future):**
- Detect if target terminal is running Claude Code (check process tree)
- If orchestrator.nvim pattern is available, send text directly via terminal channel
- Reference: `/home/jc/Dev/orchestrator.nvim/` uses `vim.api.nvim_chan_send(job_id, content + "\n")` for direct stdin injection
- For non-Neovim terminals: paste into terminal (which puts text into Claude Code's input buffer)

### 4.2 Recording Cache & Recovery

**Purpose:** Never lose audio from transient API failures.

**Storage:** `~/.local/state/symmetria/stt-cache/`

**Behavior:**
- On recording stop: save audio file to cache with metadata
- On successful transcription: delete cached audio (if `cache.deleteOnSuccess` is true)
- On failure: keep cached audio, show retry option
- Configurable: `maxEntries` (default 10), `deleteOnSuccess` (default true)

**Cache metadata file** (`~/.local/state/symmetria/stt-cache/index.json`):
```json
[
    {
        "id": "uuid",
        "timestamp": "2026-02-20T15:30:00Z",
        "language": "en",
        "duration": 45.2,
        "audioFile": "recording_001.wav",
        "status": "failed",
        "error": "Connection timed out",
        "targetWindow": "com.mitchellh.ghostty",
        "deliveryMode": "clipboard"
    }
]
```

**UI integration:** Retry button in error state reads from cache and re-submits.

### 4.3 Transcription Queue

**Purpose:** Enable continuous dictation flow — record → submit → record again while previous job processes.

**Architecture:**
```
┌─────────────────────────────────────────────┐
│  SttService.qml                              │
│                                              │
│  activeRecording: { state, audioLevel, ... } │ ← What the UI shows
│                                              │
│  jobQueue: [                                 │
│    { id, audioFile, lang, targetWindow,      │
│      status: "processing", result: null },   │
│    { id, audioFile, lang, targetWindow,      │
│      status: "pending", result: null },       │
│  ]                                           │
└─────────────────────────────────────────────┘
```

**Flow:**
1. User records, presses Submit
2. Audio saved to temp file, transcription job created and enqueued
3. Service immediately returns to `idle` — user can start recording again
4. Job processes in background (curl to API)
5. On job completion:
   - If target window matches another pending job's target → wait for that job first (FIFO per-window)
   - Otherwise → deliver immediately
6. Notification shown in drawer for each completed job

**Per-window FIFO ordering:**
- Jobs targeting the same window are delivered in submission order
- Jobs targeting different windows deliver independently as they complete
- Prevents text interleaving in a single window

### 4.4 Transcription History Drawer

**Purpose:** Dedicated UI for browsing past transcriptions (separate from system clipboard).

**Concept:** New drawer (or tab in existing clipboard drawer) showing:
- Timestamp
- Source language badge (EN/ES)
- Duration
- Target window name/class
- Working directory (if target was a terminal)
- Transcription text preview (expandable)
- Re-deliver button (paste again to any window)
- Copy button

**Storage:** `~/.local/state/symmetria/stt-history.json`

**Integration:** Accessible via IPC: `qs -c symmetria ipc call drawers toggle stt-history`

### 4.5 Long-Form Recording

**Purpose:** Support dictation sessions longer than 25 minutes.

**Strategy:** Automatic segmentation based on file size or duration threshold:
- When recording duration approaches limit (e.g., 20 min), automatically save segment and start new one
- On submit: upload all segments, concatenate transcriptions
- Alternatively: use OGG Opus compression (25MB ≈ 2-3 hours) to push the limit far enough that segmentation is rarely needed

**Context preservation:** For segment boundaries, include 2-3 seconds of audio overlap. Post-process to deduplicate overlapping text.

### 4.6 Multi-Backend Support

**Purpose:** Allow users to choose their transcription provider.

**Planned backends:**

| Backend | Config value | API | Price/hr | Notes |
|---------|-------------|-----|----------|-------|
| OpenAI GPT-4o Transcribe | `"openai"` | REST | $0.36 | Best accuracy (MVP) |
| OpenAI GPT-4o Mini Transcribe | `"openai-mini"` | REST | $0.18 | Budget option |
| Groq Whisper | `"groq"` | REST | $0.03-0.11 | Cheapest cloud, 164x real-time |
| Local whisper.cpp | `"local"` | CLI | Free | Offline, privacy-first |
| Local faster-whisper | `"local-fw"` | CLI | Free | GPU-accelerated |
| OpenRouter (multimodal) | `"openrouter"` | REST | Expensive | Only if they add dedicated STT |

**Backend interface:**
```
input: audio file path, language code
output: transcribed text (string) or error
```

Each backend implements this interface. SttService calls the active backend without knowing its internals.

### 4.7 Live Transcription Preview

**Purpose:** Show partial transcription results as they arrive (streaming).

**Feasibility:** OpenAI's `gpt-4o-transcribe` supports SSE streaming. We could show words appearing in real-time in the drawer during the "processing" state.

**Complexity:** High — requires streaming HTTP parsing in QML (or a helper process).

---

## 5. Migration Plan

### Phase 1: MVP (this implementation)
- Build SttService with pw-record + OpenAI API
- Clipboard-only delivery
- Recording cache for retry on failure
- Rename module from `hyprwhspr` to `stt`
- Update keybindings to `stt` IPC target
- Remove HyprWhspr daemon dependency

### Phase 2: Smart Delivery
- Implement window targeting (Mode B/C)
- Window capture at submit time
- Clipboard backup/restore injection pattern (from Snippet Manager)
- Terminal vs GUI paste shortcut detection

### Phase 3: Transcription Queue
- Job queue data structure
- Background processing while recording continues
- Per-window FIFO delivery ordering
- Queue status UI in drawer

### Phase 4: History & Polish
- Transcription history drawer/tab
- Long-form recording support
- Multi-backend support
- Live transcription preview (streaming SSE)

---

## 6. Reference Projects

| Project | Location | Relevant Pattern |
|---------|----------|-----------------|
| **Snippet Manager** | `/home/jc/Dev/snippet-manager/` | Clipboard backup/restore injection, `hyprctl dispatch sendshortcut`, terminal detection |
| **orchestrator.nvim** | `/home/jc/Dev/orchestrator.nvim/` | Terminal stdin injection via `nvim_chan_send()`, Claude Code direct communication |
| **HyprWhspr Integration** | `docs/hyprwhspr-integration.md` | Current state machine, UI patterns, what to preserve |
| **RFC Discussion** | [GitHub #24](https://github.com/CaceresCallieri/symetria-shell/discussions/24) | Architectural context, Proposal A/B analysis |

---

## 7. Non-Goals (for MVP)

- Local/offline transcription (future multi-backend)
- Live transcription preview / streaming (future)
- Multi-language in single session (future)
- Speaker diarization (future)
- Audio ducking during recording (HyprWhspr feature, low priority)
- Filler word filtering (can be done in post-processing later)
- Hallucination detection (GPT-4o Transcribe already handles this well)
