# Spec: Streaming STT (Live Transcription)

> **Status:** Design / spec-driven — not yet implemented
> **Date:** 2026-06-16
> **Author:** Discussion between user and Claude Code
> **Relation:** Adds a *second* transcription mode alongside the existing batch pipeline (`docs/stt-design-decisions.md`, `docs/PRD-stt-system.md`). Batch is NOT replaced — it stays as the path for long-form dictation. This document supersedes the "Live Transcription Preview (Streaming)" stub in `docs/stt-future-work.md`.

---

## 1. Overview

### Problem

The current STT pipeline is *batch*: `pw-record` writes a `.wav`, and on stop `stt-transcribe.sh` makes a single `curl` POST. The user never sees text until after they stop speaking. There is no way to read along, catch a mishearing, and re-say it on the fly.

### Solution

Add a **streaming mode** that shows partial transcripts *while recording*, fed by a backend-agnostic helper process. The user reads the live text and corrects verbally (re-says a misheard phrase) before the final text is delivered.

### The real goal — clarified

Streaming does **not** transcribe more accurately than batch. A batch pass over the complete audio generally produces the *best* final text because it sees full context. What streaming buys is **control**: seeing the text arrive lets the user re-dictate mistakes immediately. The value is confidence over what gets sent, not raw model accuracy. This framing drives the design — partials are a *preview surface*, and (optionally, see §10) the delivered text can still come from a high-quality batch pass.

### Strategic direction

Streaming is where the field is heading: prices keep falling and quality keeps rising. The long-term expectation is that streaming becomes the default and batch is reserved for very long takes. We build the streaming layer now, backend-agnostic, so we can swap engines (local ↔ cloud) without touching the UI or delivery code.

### Guiding principles

- **Two modes, one delivery.** Batch and streaming coexist; both feed the *same* delivery chain (clipboard/inject/submit) at the existing target captured in `start()`.
- **Backend-agnostic.** Local, OpenAI, and Deepgram are interchangeable implementations *behind* a fixed helper contract. QML and `SttJob` never know which ran.
- **Local-first.** Validate the entire plumbing against a free, private local engine before paying for any cloud provider.
- **Reuse, don't rebuild.** Everything downstream of the final transcript (target-locking, delivery modes, voice tag, history retention) is unchanged.

---

## 2. Architecture

### High-level

```
                       ┌──────────────────────────────────────────┐
  pw-record (PCM) ──►  │  tee / fan-out                           │
                       │   ├──► .wav file   (safety net + hybrid)  │
                       │   ├──► level monitor (audioLevel)         │
                       │   └──► stt-stream helper (stdin: raw PCM) │
                       └───────────────┬──────────────────────────┘
                                       │  stdout: JSON-lines events
                                       ▼
                        ┌──────────────────────────────┐
                        │  SttJob.qml                  │
                        │   Process + SplitParser      │
                        │   • partial → partialTranscript (live preview)
                        │   • final   → authoritative text
                        └───────────────┬──────────────┘
                                        │  final text
                                        ▼
                        ┌──────────────────────────────┐
                        │  EXISTING delivery chain      │
                        │  clipboard / inject / submit  │
                        │  (target captured at start)   │
                        └──────────────────────────────┘
```

### The agnostic helper contract

The streaming helper (`scripts/stt-stream.py`, language TBD — Python is the pragmatic choice for WebSocket + audio) is the single integration point. It:

- **Consumes** raw PCM (`s16le`, mono) on **stdin** — fed by the `pw-record` fan-out.
- **Emits** newline-delimited JSON on **stdout** — one event per line.
- Selects a backend internally via `--backend`; all backends normalize to the *same* event stream.

This mirrors the existing `stt-level-monitor.sh` → `Process` + `SplitParser` pattern already proven in the codebase for the waveform.

**Invocation (spawned by `SttJob` like the other helpers):**

```
stt-stream.py --backend <local|openai|deepgram|google> \
              [--model <id>] [--lang es] [--sample-rate <hz>]
# reads PCM from stdin, writes JSON events to stdout
```

### Wire protocol (stdout, one JSON object per line)

```json
{"type":"ready"}
{"type":"partial","text":"hola que tal como"}
{"type":"partial","text":"hola qué tal, cómo andás"}
{"type":"final","text":"Hola, qué tal, cómo andás."}
{"type":"error","detail":"websocket closed: 1006"}
```

| Event | Meaning | QML action |
|-------|---------|-----------|
| `ready` | Backend connected, accepting audio | clear `partialTranscript`, mark stream live |
| `partial` | Interim hypothesis (REPLACES prior text, not appended) | set `partialTranscript = text` |
| `final` | Authoritative transcript for the utterance | hand `text` to delivery chain |
| `error` | Backend/connection failure | surface error; fall back per §9 |

**Why typed JSON, not plain text:** partials *replace* rather than append; we must distinguish partial vs final vs error; and it leaves room for future `vad`/`confidence` events. It is also consistent with the result JSON `stt-inject.sh` already emits.

### Lifecycle mapping to `SttJob` states

| Action | Batch (today) | Streaming |
|--------|---------------|-----------|
| `start()` | spawn `pw-record` → `.wav` | spawn `pw-record` fan-out + `stt-stream`; feed PCM; `recording`; partials flow into `partialTranscript` |
| `stop()` | finalize `.wav` → `curl` | EOF stdin → helper flushes → emits `final` → delivery chain |
| `cancel()` | SIGKILL `pw-record` | SIGKILL helper + `pw-record`; discard |
| target/delivery | unchanged | unchanged (final text only) |

State additions: a brief `processing` window after `stop()` while the backend flushes its final result.

### Audio fan-out

`pw-record` currently writes a file. Streaming also needs the live PCM, and we want to keep the `.wav` (for the existing success/recovery retention and the optional hybrid batch pass, §10). Capture is consolidated to one `pw-record` whose PCM is fanned out to: the `.wav` file, the level monitor, and the stream helper (via `tee` / a small shell pipeline, or multiple PipeWire readers — PipeWire natively multiplexes a source). Exact mechanism decided at implementation; flagged here so it isn't a surprise.

---

## 3. Configuration (`config/SttConfig.qml` additions)

```jsonc
"stt": {
  "mode": "batch",            // "batch" | "streaming" — top-level selector
  "streaming": {
    "backend": "local",       // "local" | "openai" | "deepgram" | "google"
    "showPartials": true,     // render live text in the overlay
    "local": {
      "engine": "faster-whisper",  // "faster-whisper" | "whisper.cpp"
      "model": "large-v3",
      "device": "cuda",       // "cuda" | "cpu"
      "computeType": "float16", // REQUIRED on RTX 50-series — int8 is broken (§4)
      "resident": false        // manual on/off toggle (§5); also flippable via IPC
    }
  }
}
```

`mode` lets the user pick batch vs streaming per their need (long-form note → batch; live message → streaming). The `streaming.backend` is the agnostic switch. `local.resident` is the manual engine toggle (see §5), also controllable at runtime via IPC.

---

## 4. Backends

### Local (Fase 0–1) — faster-whisper / whisper.cpp on RTX 5070

Hardware: **NVIDIA RTX 5070 Laptop, 8 GB VRAM, CUDA** (Blackwell, sm_120) + Ryzen AI 7 350 (16 threads), 30 GB RAM.

**Quality:** Whisper `large-v3` is Whisper-grade Spanish (same model as OpenAI's, reimplemented faster). Local quality is NOT the weak point; latency/partial smoothness is the thing to tune.

**Blackwell constraint (critical):** RTX 50-series (sm_120) has a known CTranslate2 incompatibility — **INT8 crashes** (`cuBLAS NOT_SUPPORTED`). Use **`float16`** (~3 GB VRAM for large-v3, fits 8 GB). faster-whisper does NOT need PyTorch (it runs on CTranslate2), so the WhisperX/torch CUDA matrix does not apply — only CTranslate2 + the CUDA runtime libs matter.

**Verified setup (2026-06-16) — confirmed working on the RTX 5070.** float16 loads and transcribes on this Blackwell GPU; no int8 crash. The recipe:

```sh
# isolated venv (Arch python is PEP 668 externally-managed; no system pip)
python3 -m venv ~/.local/share/symmetria/stt-venv
~/.local/share/symmetria/stt-venv/bin/pip install faster-whisper        # pulls ctranslate2 4.8.0 (cp314 wheel, sm_120-capable)
~/.local/share/symmetria/stt-venv/bin/pip install nvidia-cublas-cu12 nvidia-cudnn-cu12   # 12.9 / 9.23 — NOT bundled by the ctranslate2 wheel
```

**Launch gate:** the ctranslate2 wheel does not bundle cuBLAS/cuDNN, so the helper must be spawned with `LD_LIBRARY_PATH` pointing at the pip-installed nvidia lib dirs. `LD_LIBRARY_PATH` is read by the dynamic linker at exec — it CANNOT be set reliably from inside the already-started Python process (glibc caches it). So the QML `Process` command must be `env LD_LIBRARY_PATH=<cublas_dir>:<cudnn_dir> <venv>/bin/python stt-stream.py ...`. Compute the dirs from the namespace packages' `__path__` (their `__file__` is `None`):

```sh
CUBLAS_DIR=$(dirname "$(find ~/.local/share/symmetria/stt-venv -name 'libcublas.so.12' | head -1)")
CUDNN_DIR=$(dirname "$(find ~/.local/share/symmetria/stt-venv -name 'libcudnn.so*' | head -1)")
```

Measured: `small` transcribed 38 s of Spanish in ~4.9 s wall (model cached, 6 buffer re-transcribes) — faster than real-time. `small` mangles technical Spanish vocab; `large-v3` is the Fase 1 quality model.

**Local engine choice:**

| Approach | Pros | Cons | Use |
|----------|------|------|-----|
| **`mock` backend** | no engine, no GPU; emits partials derived from received audio | not real transcription | **Fase 0** — validates the full plumbing (stdin → events → QML) for free |
| **faster-whisper** | Whisper-grade Spanish, fits the PCM-stdin contract (we feed it), built-in VAD | Python runtime, Blackwell setup gate (float16) | **Fase 0/1** — real local transcription; partials by re-transcribing the growing buffer (self-corrects with context) |

> **Why not whisper.cpp `stream`** (originally floated for Fase 0): its `stream` example **captures its own microphone via SDL** and does not read PCM from stdin — it would bypass the `pw-record` fan-out and break the agnostic contract. whisper.cpp remains usable as an alternative engine only if driven file/chunk-wise (`whisper-cli`), which just re-implements what faster-whisper already does. So Fase 0 ships `mock` + `faster-whisper`.

**CPU fallback:** faster-whisper runs on the Ryzen (16 threads) with **zero VRAM**. `large-v3` on CPU is borderline for streaming; `medium`/`small` work. This is the "dictate while gaming without touching the GPU" path.

### Cloud (Fase 2 — benchmark behind the same contract)

| Backend | Transport | Audio in | Partial events | Price | Setup friction |
|---------|-----------|----------|----------------|-------|----------------|
| **OpenAI `gpt-realtime-whisper`** | WebSocket | 24 kHz mono PCM | `input_audio_transcription.delta` / `.completed` | ~$0.017/min (~$1.02/hr, token-billed — approx) | **Lowest** — reuses existing `OPENAI_API_KEY`, prompt/vocab concepts |
| **Deepgram Nova-3** | WebSocket | linear16 (accepts 16 kHz) | interim results | $0.0077/min ($0.46/hr) | New API key; lowest latency, cheapest real streaming |
| **Google Chirp 3** | gRPC `StreamingRecognize` | LINEAR16 | interim results | $0.016/min ($0.96/hr) | **Highest** — GCP + service-account creds + gRPC client |

All three plug in as `stt-stream.py --backend <x>`, emitting the same JSON-lines protocol. QML is untouched when switching.

---

## 5. VRAM, battery & the manual toggle

A loaded-but-idle model costs ~nothing in *compute* power — but on an NVIDIA laptop an **active CUDA context keeps the dGPU out of its deep sleep state (RTD3)**, costing several watts continuously. That is the real battery cost, and it is why a **manual on/off toggle is preferred over an idle-timeout**: an idle-timeout that only unloads model weights leaves the daemon (and CUDA context) alive, so the dGPU stays awake and the battery isn't recovered. Only **killing the engine process** lets the dGPU sleep.

| Toggle (`local.resident` / IPC) | Engine state | Dictation latency | VRAM / battery |
|---|---|---|---|
| **ON** (plugged in, working) | daemon up, model resident | instant | ~3 GB, dGPU awake |
| **OFF** (gaming, on battery) | daemon killed | cold-start ~3 s **or** auto-route to cloud | 0 GB, dGPU sleeps |

"OFF" does not mean broken: triggering STT with the engine off either cold-starts it (few seconds) or routes to a configured cloud backend. The toggle lives in the shell (Quickshell control + IPC `stt engine on|off`) — one explicit action, no magic.

---

## 6. Cost comparison (verified, Jun 2026)

| Engine | Mode | $/min | $/hr | vs. batch actual | Notes |
|--------|------|------:|-----:|-----------------:|-------|
| `gpt-4o-transcribe` (current) | batch | $0.006 | $0.36 | — | stays for long-form |
| Local (whisper.cpp / faster-whisper) | streaming | $0 | $0 | free | + VRAM/battery cost while resident |
| Deepgram Nova-3 | streaming | $0.0077 | $0.46 | 1.3× | cheapest real streaming, lowest latency |
| Google Chirp 3 | streaming | $0.016 | $0.96 | 2.7× | heaviest setup |
| OpenAI `gpt-realtime-whisper` | streaming | ~$0.017 | ~$1.02 | 2.8× | lowest integration friction |

For personal use (~30 min/day ≈ 15 h/mo): current ≈ $5.40/mo, Deepgram ≈ $6.90/mo, OpenAI realtime ≈ $15.30/mo. The dollar delta is small; the decision is quality (Spanish-AR), latency, and — for a gaming laptop — whether to spend VRAM locally or offload to cloud.

---

## 7. Phased roadmap

| Fase | Scope | Goal |
|------|-------|------|
| **0 — Plumbing** | `scripts/stt-stream.py` helper (backends `mock` + `faster-whisper`) → `pw-record` fan-out → `partialTranscript` → live display in drawer + bar embed. Delivery chain untouched. | Prove the system works end-to-end, free. |
| **1 — Local quality** | faster-whisper `large-v3` float16 + VAD; manual resident toggle + IPC; CPU fallback. | Measure Spanish-AR quality/latency. Maybe never need cloud. |
| **2 — Cloud benchmark** | Same helper, backends `openai` / `deepgram` / `google`, real user audio. | Decide if the relative price step is worth it over local. |
| **3 — Hybrid (optional)** | Stream for preview + batch `gpt-4o-transcribe` on the retained `.wav` for the *delivered* text. | Live feedback + max final accuracy for important takes. |

---

## 8. Codebase touch points

| File | Change |
|------|--------|
| `scripts/stt-stream.py` (new) | The agnostic helper: PCM stdin → JSON-lines stdout; pluggable backends |
| `config/SttConfig.qml` | Add `mode`, `streaming{}` sub-schema (§3) |
| `services/SttJob.qml` | Streaming code path: spawn helper, consume deltas → new `partialTranscript` property, route `final` into existing delivery |
| `modules/recorder/Content.qml` | Render `partialTranscript` live during recording |
| `modules/recorder/RecordingBarEmbed.qml` | Show partial text (compact) in merge mode |
| `modules/recorder/RecorderRoot.qml` | IPC: `stt engine on|off`, maybe `stt mode batch|streaming` |
| `scripts/` (audio fan-out) | `tee`/pipeline so one `pw-record` feeds wav + level monitor + helper |

What is explicitly **unchanged**: target capture/locking, delivery modes (clipboard/inject/submit), voice tag, Neovim RPC injection, history/recovery retention. Streaming sits *above* the final-transcript boundary.

---

## 9. Open questions / risks

- **Blackwell setup (RESOLVED 2026-06-16):** float16 + ctranslate2 4.8.0 confirmed loading and transcribing on this RTX 5070 — see the verified recipe in §4. The remaining gate is purely the `LD_LIBRARY_PATH` launch wiring (the helper's QML `Process` command must inject the nvidia lib dirs). whisper.cpp (CUDA/Vulkan) stays as a fallback only if a future ctranslate2 regresses sm_120 support.
- **Partial UX:** interim text flickers/revises. Need a display treatment (e.g. dim the unstable tail) so the live preview is readable, not jittery.
- **Audio fan-out mechanism:** `tee` vs multiple PipeWire readers vs a named pipe — pick the one that doesn't drop samples under load.
- **Final-vs-partial reconciliation:** the streamed `final` may differ from the last `partial`; the delivered text must be the `final` (or, in Fase 3, the batch result).
- **OpenAI realtime billing:** ~$0.017/min is approximate (audio-token billed); confirm with the actual account during Fase 2.
- **Helper language:** Python is pragmatic (WebSocket + audio libs) but adds a runtime; whisper.cpp `stream` (Fase 0) needs no Python at all.

---

## 10. Hybrid mode (Fase 3 detail)

Because the `.wav` is already retained (success/recovery net), we can decouple *preview* from *delivery*:

- During recording: any streaming backend (even a cheap/local one) drives the live `partialTranscript`.
- On stop: fire a batch `gpt-4o-transcribe` pass on the retained `.wav`; the **batch result is the delivered text**.

This gives live feedback *and* maximum final accuracy, layered on top of the existing robust pipeline. Cost is additive (stream + batch) but, per §6, negligible in absolute terms for personal use. Opt-in per the user's need for a given take.

---

## 11. Non-goals

- Replacing batch (it stays for long-form).
- Speaker diarization, multi-language-per-utterance (deferred).
- Auto-switching engines without user intent (the toggle is explicit by design).

---

## 12. References

- OpenAI realtime transcription: https://developers.openai.com/api/docs/guides/realtime-transcription
- Deepgram STT comparison 2026: https://deepgram.com/learn/best-speech-to-text-apis-2026
- Open-source STT benchmarks 2026: https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks
- WhisperLive (local streaming server): https://github.com/collabora/WhisperLive
- faster-whisper: https://github.com/SYSTRAN/faster-whisper
- Blackwell/sm_120 CTranslate2 fix (WhisperX PR #1182): https://github.com/SubtitleEdit/subtitleedit/issues/10180
- Google Speech-to-Text pricing: https://cloud.google.com/speech-to-text/pricing
