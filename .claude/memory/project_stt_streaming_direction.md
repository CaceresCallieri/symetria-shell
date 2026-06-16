---
name: project_stt_streaming_direction
description: "STT streaming is the next major workstream — backend-agnostic, local-first; batch stays for long-form"
metadata: 
  node_type: memory
  type: project
  originSessionId: 00be2313-f24f-4203-801f-ec46561b9ef4
---

Decided 2026-06-16. The STT system gains a **streaming mode** alongside the existing batch pipeline (which is NOT replaced — batch stays for long-form dictation). Streaming is the strategic direction: as prices fall / quality rises, streaming becomes default, batch reserved for very long takes.

**Key design decisions (full spec: `docs/stt-streaming-spec.md`):**
- **Agnostic interface**: a helper `scripts/stt-stream.py` consumes raw PCM on stdin, emits newline-delimited JSON events (`partial`/`final`/`error`) on stdout. QML reads via `Process`+`SplitParser` (same pattern as `stt-level-monitor.sh`). Local/OpenAI/Deepgram/Google are interchangeable backends *behind* this contract — QML never knows which ran.
- **"Precision" clarification**: streaming does NOT transcribe more accurately. Its value is live *control* — the user reads partials and re-dictates mishearings verbally before delivery. Batch over full audio is generally more accurate.
- **Local-first roadmap**: Fase 0 plumbing (whisper.cpp `stream`, free, prove the system) → Fase 1 local quality (faster-whisper large-v3 + VAD) → Fase 2 cloud benchmark → Fase 3 optional hybrid (stream preview + batch gpt-4o final on the retained .wav).
- **Hardware**: user's GPU is RTX 5070 Laptop, 8 GB VRAM, Blackwell sm_120. CRITICAL: CTranslate2 INT8 is broken on sm_120 (`cuBLAS NOT_SUPPORTED`) — MUST use **float16**. VERIFIED WORKING 2026-06-16: float16 + ctranslate2 4.8.0 (cp314 wheel) transcribes on this GPU. Setup: venv at `~/.local/share/symmetria/stt-venv`, `pip install faster-whisper nvidia-cublas-cu12 nvidia-cudnn-cu12`, and launch the helper with `env LD_LIBRARY_PATH=<nvidia cublas+cudnn lib dirs>` (linker reads it at exec; can't be set in-process). faster-whisper does NOT need PyTorch. Full recipe in `docs/stt-streaming-spec.md` §4.
- **Manual on/off toggle, NOT idle-timeout**: user rejected idle-timeout as a hack. Real reason it's correct: an active CUDA context keeps the laptop dGPU out of deep sleep (RTD3) → battery cost. Idle-timeout that only unloads weights leaves the process/context alive → dGPU stays awake. Only killing the engine process recovers battery. Toggle ON = resident/instant; OFF = cold-start or cloud-route. CPU fallback exists for "dictate while gaming without touching the GPU".

**Why:** user wants to see the message as it's transcribed to correct on the fly, and to future-proof the system for streaming-first. **How to apply:** when implementing, build to the agnostic helper contract; don't hardcode a provider. Everything downstream of the `final` transcript (target-locking, delivery modes, voice tag, retention) is unchanged. Verified cost (Jun 2026): batch gpt-4o $0.36/hr, Deepgram Nova-3 $0.46/hr, Google Chirp3 $0.96/hr, OpenAI gpt-realtime-whisper ~$1.02/hr. Related: [[project_cli_consolidation_progress]].
