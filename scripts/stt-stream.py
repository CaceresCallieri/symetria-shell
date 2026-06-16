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
import ctypes
import json
import os
import signal
import subprocess
import sys

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


def _silence_broken_stdout() -> None:
    """Point fd 1 at /dev/null after a broken pipe.

    Python flushes sys.stdout's buffer again at interpreter shutdown; if the
    pipe is already broken that flush re-raises and prints a stray "Exception
    ignored ... BrokenPipeError" to stderr. Redirecting the fd makes the
    shutdown flush go nowhere, silently.
    """
    try:
        devnull = os.open(os.devnull, os.O_WRONLY)
        os.dup2(devnull, sys.stdout.fileno())
    except OSError:
        pass


def _emit_error_safe(detail: str) -> None:
    """Emit an error event, swallowing a dead-pipe failure during reporting.

    If the QML parent has already gone away the pipe is broken, so writing the
    error would itself raise BrokenPipeError; there is no one left to read it.
    """
    try:
        emit({"type": "error", "detail": detail})
    except BrokenPipeError:
        _silence_broken_stdout()


def _spawn_capture(source: str, sample_rate: int, channels: int) -> subprocess.Popen:
    """Spawn pw-record as a child reading the mic, returning the Popen.

    The helper owning pw-record (rather than a `sh -c "pw-record | helper"`
    pipeline) means a single process for QML to manage: signalling the helper
    cleans up capture too, with no orphaned grandchildren. PR_SET_PDEATHSIG
    makes pw-record receive SIGTERM if THIS helper dies for ANY reason
    (including an uncatchable SIGKILL), so it can never be left holding the
    PipeWire source.
    """
    args = ["pw-record", "--format=s16", f"--rate={sample_rate}", f"--channels={channels}"]
    if source:
        args.append(f"--target={source}")
    args.append("-")

    def _set_pdeathsig() -> None:
        try:
            # PR_SET_PDEATHSIG = 1
            ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)
        except Exception:
            pass

    return subprocess.Popen(args, stdout=subprocess.PIPE, preexec_fn=_set_pdeathsig)


def pcm_bytes_to_float32(pcm: bytes):
    """Convert s16le PCM bytes to a normalized float32 numpy array in [-1, 1].

    A pipe read can split a 2-byte sample, leaving the accumulated buffer an
    odd length; np.frombuffer raises on that, so trim the trailing byte (it
    rejoins its pair once the next read arrives).
    """
    import numpy as np

    usable = len(pcm) - (len(pcm) % BYTES_PER_SAMPLE)
    return np.frombuffer(pcm[:usable], dtype=np.int16).astype(np.float32) / 32768.0


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


def _positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return parsed


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
        "--capture",
        action="store_true",
        help="spawn pw-record internally instead of reading PCM from stdin",
    )
    parser.add_argument("--source", default="", help="PipeWire source node (with --capture)")
    parser.add_argument(
        "--channels", type=_positive_int, default=1, help="capture channels (with --capture)"
    )
    parser.add_argument(
        "--sample-rate",
        dest="sample_rate",
        type=_positive_int,
        default=16000,
        help="PCM rate (positive int)",
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
    # QML tears the helper down with SIGTERM (its Process kills the child on
    # cancel). Translate that into KeyboardInterrupt so a cancel landing
    # anywhere -- read loop OR final flush -- unwinds to the single handler
    # below that discards the take without emitting a final. A normal stop()
    # instead closes stdin (EOF), which falls through to the final emission.
    # SIGINT keeps its default (also KeyboardInterrupt), so Ctrl+C during
    # manual testing cancels cleanly too.
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))

    backend = build_backend(args)
    emit({"type": "ready"})

    tick_bytes = max(1, int(args.sample_rate * TICK_SECONDS) * BYTES_PER_SAMPLE)
    # Never let the partial cadence outrun one tick: a non-positive
    # --partial-interval would otherwise re-transcribe the whole buffer every
    # 100ms and flood the engine.
    interval_bytes = max(
        tick_bytes, int(args.sample_rate * args.partial_interval) * BYTES_PER_SAMPLE
    )
    bytes_since_partial = 0
    last_partial = None

    # Audio source: either pw-record we own (--capture) or PCM piped to stdin.
    capture_proc = (
        _spawn_capture(args.source, args.sample_rate, args.channels)
        if args.capture
        else None
    )
    stream = capture_proc.stdout if capture_proc is not None else sys.stdin.buffer
    try:
        while True:
            chunk = stream.read(tick_bytes)
            if not chunk:  # EOF: source closed -> stop() finalizes the take.
                break
            backend.feed(chunk)
            bytes_since_partial += len(chunk)
            if bytes_since_partial >= interval_bytes:
                bytes_since_partial = 0
                text = backend.partial()
                if text and text != last_partial:
                    last_partial = text
                    emit({"type": "partial", "text": text})
        emit({"type": "final", "text": backend.final()})
    except KeyboardInterrupt:
        # Cancellation (SIGTERM/SIGINT) discards the take; emit nothing.
        return 0
    except BrokenPipeError:
        # The QML parent went away; its pipe is gone, so there is nothing left
        # to report and flushing again would only re-raise.
        _silence_broken_stdout()
        return 0
    except Exception as exc:  # noqa: BLE001 - any failure becomes an error event
        _emit_error_safe(str(exc))
        return 1
    finally:
        # PR_SET_PDEATHSIG already covers a hard kill; this is the graceful path.
        if capture_proc is not None:
            try:
                capture_proc.terminate()
                capture_proc.wait(timeout=1)
            except Exception:
                try:
                    capture_proc.kill()
                except Exception:
                    pass
    return 0


def main() -> int:
    # Force UTF-8 on the output streams regardless of the spawn locale: the
    # wire protocol carries Spanish text (qué, andás) via ensure_ascii=False,
    # and QML may launch us without a UTF-8 locale, which would otherwise raise
    # UnicodeEncodeError on the first accented partial.
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

    args = parse_args(sys.argv[1:])
    try:
        return run(args)
    except Exception as exc:  # noqa: BLE001 - any setup failure -> structured error
        # Setup-time failures (bad backend, missing engine, CUDA/CTranslate2
        # init on the Blackwell path) are reported as a structured error so QML
        # surfaces a hint instead of a bare traceback. Engine init runs before
        # run()'s own try, so non-RuntimeError exception types must be caught
        # here too.
        _emit_error_safe(str(exc))
        return 1


if __name__ == "__main__":
    sys.exit(main())
