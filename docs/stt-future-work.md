# STT: Future Work

> Remaining feature ideas from the original [PRD](https://github.com/CaceresCallieri/symetria-shell/discussions/24) that were deferred beyond the initial implementation.
> See CLAUDE.md's "Native Speech-to-Text (STT)" section for documentation of everything already shipped.

---

## What's Already Done

| Phase | Scope | Status |
|-------|-------|--------|
| **Phase 1 — MVP** | pw-record capture, audio level monitor, OpenAI API, clipboard delivery, full state machine, IPC, config, pause/resume | Shipped |
| **Phase 2 — Smart Delivery** | Window inject (Mode B), auto-submit (Mode C), "ask" runtime radio, terminal detection, Neovim RPC injection | Shipped |

---

## Persistent Recording Cache

**Priority:** Medium
**Purpose:** Never lose audio from transient API failures.

Current state: basic in-memory retry works (audio file kept on disk, `retry()` re-submits it). Missing: persistent metadata index for cross-session recovery.

**Full vision:**

Storage: `~/.local/state/symmetria/stt-cache/`

Metadata file (`index.json`):
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

Behavior:
- On recording stop: save audio + metadata to cache
- On success: delete cached audio (if `cache.deleteOnSuccess`)
- On failure: persist for retry across shell restarts
- Configurable: `maxEntries` (default 10)

---

## Transcription Queue

**Priority:** Medium
**Purpose:** Continuous dictation — record again while the previous job is still transcribing.

Architecture:
```
SttService.qml
├── activeRecording: { state, audioLevel, ... }  ← UI shows this
└── jobQueue: [
      { id, audioFile, lang, targetWindow, status: "processing" },
      { id, audioFile, lang, targetWindow, status: "pending" },
    ]
```

Flow:
1. User records + submits → job enqueued, service returns to `idle`
2. User can immediately start a new recording
3. Jobs process in background (curl → API)
4. Per-window FIFO ordering prevents text interleaving
5. Toast notification per completed job

Key decisions:
- Jobs targeting the same window deliver in submission order
- Jobs targeting different windows deliver independently
- Queue status visible in drawer UI

---

## Transcription History Drawer

**Priority:** Low
**Purpose:** Browse past transcriptions (separate from system clipboard).

Concept — new drawer (or tab in clipboard drawer):
- Timestamp, language badge (EN/ES), duration
- Target window name/class
- Transcription text preview (expandable)
- Re-deliver / copy buttons

Storage: `~/.local/state/symmetria/stt-history.json`
IPC: `qs -c symmetria ipc call drawers toggle stt-history`

---

## Long-Form Recording

**Priority:** Low
**Purpose:** Dictation sessions longer than 25 minutes (OpenAI's 25MB file limit).

Strategies:
- **Auto-segmentation:** When duration approaches ~20 min, save segment automatically + start new one. On submit, upload all segments and concatenate transcriptions.
- **Compression:** OGG Opus encoding (25MB ≈ 2-3 hours) pushes the limit far enough that segmentation is rarely needed.
- **Overlap:** 2-3 seconds of audio overlap at segment boundaries, post-process to deduplicate text.

---

## Multi-Backend Support

**Priority:** Low
**Purpose:** Choose transcription provider (cost, privacy, offline).

| Backend | Config value | Price/hr | Notes |
|---------|-------------|----------|-------|
| OpenAI GPT-4o Transcribe | `"openai"` | $0.36 | Current default, best accuracy |
| OpenAI GPT-4o Mini Transcribe | `"openai-mini"` | $0.18 | Budget option |
| Groq Whisper | `"groq"` | $0.03-0.11 | Cheapest cloud, 164x real-time |
| Local whisper.cpp | `"local"` | Free | Offline, privacy-first |
| Local faster-whisper | `"local-fw"` | Free | GPU-accelerated |

Backend interface:
```
input:  audio file path (language auto-detected by gpt-4o-transcribe — `lang` param was removed)
output: transcribed text (string) or error
```

Each backend implements this contract. `SttService` calls the active backend without knowing its internals.

---

## Client-Side Chunking for Long Audio (keep gpt-4o on long takes)

**Priority:** Medium
**Complexity:** Medium
**Purpose:** Transcribe long recordings with `gpt-4o-transcribe` without hitting its silent output-token truncation (~10 min), preserving its accuracy and paragraph formatting.

Current mitigation routes long recordings to `whisper-1` (see `stt-design-decisions.md` → *Model Selection & Long-Audio Truncation*), which is complete but loses paragraph formatting and is slightly less accurate. A better long-term path: split the recorded WAV into <10-min chunks (e.g. via `ffmpeg -f segment`, ideally on silence boundaries to avoid mid-word cuts), transcribe each chunk with gpt-4o-transcribe, and concatenate. The multi-segment ffmpeg-concat infra in `SttJob` exists for pause/resume and could be adapted for *size*-based splitting. Caveats: chunk boundaries can drop/duplicate a word; per-chunk prompt priming needs care for cross-chunk continuity.

---

## Live Transcription Preview (Streaming)

**Priority:** Low
**Complexity:** High
**Purpose:** Show partial transcription as words arrive during the "processing" state.

OpenAI's `gpt-4o-transcribe` supports SSE streaming. Implementation would require streaming HTTP parsing in either a helper process or C++ plugin.

---

## Deferred Ideas (No Plans Yet)

- Multi-language in a single session
- Speaker diarization
- Audio ducking during recording
- Filler word filtering (post-processing)
- C++ PipeWire plugin for zero-overhead audio level (replace shell pipeline)

---

## Reference Projects

| Project | Location | Relevant Pattern |
|---------|----------|-----------------|
| **Snippet Manager** | `/home/jc/Dev/snippet-manager/` | Clipboard injection, `sendshortcut`, terminal detection |
| **orchestrator.nvim** | `/home/jc/Dev/orchestrator.nvim/` | Neovim terminal stdin injection via `nvim_chan_send()` |
| **RFC Discussion** | [GitHub #24](https://github.com/CaceresCallieri/symetria-shell/discussions/24) | Original architectural context, Proposal A/B analysis |
