#!/usr/bin/env python3
"""Backend-agnostic streaming STT helper for Symmetria.

Reads raw PCM (signed 16-bit little-endian, mono) from stdin and emits
newline-delimited JSON events on stdout, one object per line:

    {"type":"ready"}
    {"type":"partial","text":"hola que tal"}
    {"type":"partial","text":"hola qué tal cómo"}
    {"type":"final","text":"Hola, qué tal, cómo andás."}
    {"type":"error","detail":"..."}

The audio fan-out (pw-record -> {wav, level monitor, this helper}) feeds the
PCM. QML consumes the events via Process + SplitParser, exactly like
stt-level-monitor.sh feeds the waveform. Backends are interchangeable behind
this contract: QML never knows which one produced the events.

See docs/stt-streaming-spec.md for the full design.

Backends:
    mock            No engine required. Emits partials derived from the audio
                    actually received, then a final. Used to validate the
                    end-to-end plumbing without a model installed.
    faster-whisper  Local Whisper (CTranslate2). On RTX 50-series (Blackwell,
                    sm_120) INT8 is broken (cuBLAS NOT_SUPPORTED) -- use
                    compute_type=float16. Requires faster-whisper installed.

Cloud backends (openai/deepgram/google) are added in Fase 2; the dispatch
table below is where they plug in.
"""

from __future__ import annotations

import argparse
import json
import signal
import sys
import time

# 16-bit mono PCM: 2 bytes per sample. One "tick" read from stdin is sized so
# QML sees events at a steady cadence, mirroring the 100ms level-monitor chunk.
BYTES_PER_SAMPLE = 2
TICK_SECONDS = 0.1


def emit(event: dict) -> None:
    """Write one JSON event as a single line and flush immediately.

    Flushing per line is essential: QML's SplitParser only sees an event once
    the newline reaches the pipe, so buffering would stall the live preview.
    """
    sys.stdout.write(json.dumps(event, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def pcm_bytes_to_float32(pcm: bytes):
    """Convert s16le PCM bytes to a normalized float32 numpy array in [-1, 1]."""
    import numpy as np

    return np.frombuffer(pcm, dtype=np.int16).astype(np.float32) / 32768.0


class MockBackend:
    """Engine-free backend that proves the plumbing.

    It does not transcribe -- it grows a placeholder transcript in proportion
    to the seconds of audio actually received, so a test can confirm that
    stdin ingestion, partial cadence, and the final flush all work.
    """

    _WORDS = (
        "hola qué tal cómo andás esto es una prueba del pipeline de streaming "
        "que muestra texto parcial mientras se graba el audio en vivo"
    ).split()

    def __init__(self, sample_rate: int, **_: object) -> None:
        self._sample_rate = sample_rate
        self._samples = 0

    def feed(self, pcm: bytes) -> None:
        self._samples += len(pcm) // BYTES_PER_SAMPLE

    def _text_for_elapsed(self) -> str:
        # ~2 words per second of audio, capped at the canned sentence length.
        seconds = self._samples / self._sample_rate
        count = min(len(self._WORDS), int(seconds * 2))
        return " ".join(self._WORDS[:count])

    def partial(self) -> str:
        return self._text_for_elapsed()

    def final(self) -> str:
        text = self._text_for_elapsed()
        return (text[:1].upper() + text[1:] + ".") if text else ""


class FasterWhisperBackend:
    """Local Whisper via CTranslate2.

    Partials are produced by re-transcribing the full buffer so far: with
    full context the hypothesis self-corrects as more audio arrives, which is
    the re-dictation UX we want (the user sees a phrase get fixed). For typical
    dictation lengths the repeated work is cheap on a faster-than-realtime GPU;
    a VAD-segmented path is a Fase 1 refinement.
    """

    def __init__(
        self,
        sample_rate: int,
        model: str,
        device: str,
        compute_type: str,
        lang: str | None,
        **_: object,
    ) -> None:
        try:
            from faster_whisper import WhisperModel
        except ImportError as exc:
            raise RuntimeError(
                "faster-whisper is not installed. Install it (e.g. "
                "`pip install faster-whisper`) with a CUDA 12.8 / CTranslate2 "
                ">=4.5.0 stack for Blackwell (sm_120) support."
            ) from exc

        self._sample_rate = sample_rate
        self._lang = lang or None
        self._buffer = bytearray()
        self._model = WhisperModel(model, device=device, compute_type=compute_type)

    def feed(self, pcm: bytes) -> None:
        self._buffer.extend(pcm)

    def _transcribe(self, beam_size: int) -> str:
        if not self._buffer:
            return ""
        audio = pcm_bytes_to_float32(bytes(self._buffer))
        segments, _ = self._model.transcribe(
            audio,
            language=self._lang,
            beam_size=beam_size,
            vad_filter=True,
            condition_on_previous_text=False,
        )
        return " ".join(seg.text.strip() for seg in segments).strip()

    def partial(self) -> str:
        return self._transcribe(beam_size=1)

    def final(self) -> str:
        return self._transcribe(beam_size=5)


BACKENDS = {
    "mock": MockBackend,
    "faster-whisper": FasterWhisperBackend,
    # Fase 2: "openai", "deepgram", "google" (WebSocket/gRPC clients) plug in here.
}


def build_backend(args: argparse.Namespace):
    factory = BACKENDS.get(args.backend)
    if factory is None:
        raise RuntimeError(
            f"unknown backend '{args.backend}'. Known: {', '.join(sorted(BACKENDS))}"
        )
    return factory(
        sample_rate=args.sample_rate,
        model=args.model,
        device=args.device,
        compute_type=args.compute_type,
        lang=args.lang,
    )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--backend", default="mock", help="mock | faster-whisper (default: mock)"
    )
    parser.add_argument("--model", default="large-v3", help="model id (local backends)")
    parser.add_argument("--device", default="cuda", help="cuda | cpu")
    parser.add_argument(
        "--compute-type",
        dest="compute_type",
        default="float16",
        help="float16 required on RTX 50-series (int8 is broken on sm_120)",
    )
    parser.add_argument("--lang", default=None, help="language hint, e.g. es")
    parser.add_argument(
        "--sample-rate", dest="sample_rate", type=int, default=16000, help="PCM rate"
    )
    parser.add_argument(
        "--partial-interval",
        dest="partial_interval",
        type=float,
        default=1.5,
        help="seconds of new audio between partial emissions",
    )
    return parser.parse_args(argv)


def run(args: argparse.Namespace) -> int:
    # SIGTERM/SIGINT (how SttJob cancels) should unwind cleanly via the read
    # loop, not dump a traceback. Raising KeyboardInterrupt lets the finally
    # block decide whether a final transcript is still warranted.
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))

    backend = build_backend(args)
    emit({"type": "ready"})

    tick_bytes = max(1, int(args.sample_rate * TICK_SECONDS) * BYTES_PER_SAMPLE)
    interval_bytes = int(args.sample_rate * args.partial_interval) * BYTES_PER_SAMPLE
    bytes_since_partial = 0
    last_partial = None
    cancelled = False

    stdin = sys.stdin.buffer
    try:
        while True:
            chunk = stdin.read(tick_bytes)
            if not chunk:  # EOF: pw-record closed -> stop() finalizes the take.
                break
            backend.feed(chunk)
            bytes_since_partial += len(chunk)
            if bytes_since_partial >= interval_bytes:
                bytes_since_partial = 0
                text = backend.partial()
                if text and text != last_partial:
                    last_partial = text
                    emit({"type": "partial", "text": text})
    except KeyboardInterrupt:
        cancelled = True
    except Exception as exc:  # noqa: BLE001 - any failure becomes an error event
        emit({"type": "error", "detail": str(exc)})
        return 1

    if cancelled:
        # Cancellation discards the take; SttJob.cancel() owns cleanup.
        return 0

    try:
        emit({"type": "final", "text": backend.final()})
    except Exception as exc:  # noqa: BLE001
        emit({"type": "error", "detail": str(exc)})
        return 1
    return 0


def main() -> int:
    args = parse_args(sys.argv[1:])
    try:
        return run(args)
    except RuntimeError as exc:
        # Setup-time failures (bad backend, missing engine) are reported as a
        # structured error so QML can surface a hint instead of a silent exit.
        emit({"type": "error", "detail": str(exc)})
        return 1


if __name__ == "__main__":
    sys.exit(main())
