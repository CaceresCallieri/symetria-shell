import Quickshell.Io

JsonObject {
    property bool enabled: true
    property string apiKey: ""
    property string backend: "openai"
    property string model: "gpt-4o-transcribe"

    // Long-audio model routing. gpt-4o-transcribe is an LLM that follows the
    // verbatim/paragraph prompt and is more accurate for short dictation, but
    // it silently truncates output at its ~2000-token ceiling (~10 min of
    // speech). whisper-1 chunks audio internally and never truncates, at the
    // cost of ignoring prompt instructions (no paragraph formatting). So
    // recordings longer than longAudioThresholdSec are routed to
    // longAudioModel instead of `model`. Set longAudioThresholdSec to 0 to
    // disable routing and always use `model`. For a blanket switch, set
    // `model` itself to "whisper-1".
    property string longAudioModel: "whisper-1"
    property int longAudioThresholdSec: 420

    // Transcription mode. "batch" is the current file-then-curl pipeline (best
    // for long-form dictation). "streaming" shows partial transcripts live
    // while recording via the scripts/stt-stream.py helper. The two coexist;
    // see docs/stt-streaming-spec.md. Default "batch" preserves current
    // behaviour until streaming is opted into.
    property string mode: "batch"

    property int autoHideDelay: 1500
    property int processingTimeout: 120000
    // Default delivery mode, seeding each new recording. Mode keys during a
    // session override it for that recording only (one-shot).
    // Valid values: "clipboard" | "inject" | "submit"
    property string deliveryMode: "clipboard"

    // Prefix prepended to transcribed text when injecting into agent-backed
    // terminals (e.g. Claude Code). Signals the LLM that input is voice-
    // transcribed and may contain STT artifacts. Empty string disables.
    property string voiceTag: "[voiced] "

    // Persistent vocabulary hints sent with every transcription to improve
    // proper noun / technical term accuracy (appended to the API prompt).
    property list<string> vocabularyHints: []

    property JsonObject recording: JsonObject {
        property string format: "wav"
        property int sampleRate: 16000
        property int channels: 1

        // PipeWire node name to record from (pw-record --target). Empty =
        // system default source. Set to "echo-cancel-source" to capture the
        // echo-cancelled microphone (requires the libpipewire-module-echo-cancel
        // drop-in in ~/.config/pipewire/pipewire.conf.d — see docs/module-setup.md).
        // If the named node does not exist, pw-record fails and recording errors.
        property string source: ""
    }

    // Streaming mode (mode === "streaming"). Backends are interchangeable
    // behind the scripts/stt-stream.py helper (PCM stdin -> JSON-lines stdout);
    // QML consumes partials the same way it consumes the waveform level. NOTE:
    // streaming.backend is distinct from the top-level `backend` above, which
    // selects the BATCH provider. See docs/stt-streaming-spec.md.
    property JsonObject streaming: JsonObject {
        // "local" | "openai" | "deepgram" | "google"
        property string backend: "local"
        // Render the live partial transcript in the recorder overlay.
        property bool showPartials: true
        // Seconds of new audio between partial emissions (helper
        // --partial-interval). Lower = snappier but more engine work.
        property real partialInterval: 1.5

        property JsonObject local: JsonObject {
            // "faster-whisper" (PCM-stdin, VAD, Whisper-grade) | "whisper.cpp"
            property string engine: "faster-whisper"
            property string model: "large-v3"
            property string device: "cuda" // "cuda" | "cpu" (cpu = zero VRAM)

            // float16 is REQUIRED on RTX 50-series (Blackwell, sm_120):
            // CTranslate2 int8 crashes there (cuBLAS NOT_SUPPORTED). Needs
            // CTranslate2 >=4.5.0 / CUDA 12.8. See docs/stt-streaming-spec.md.
            property string computeType: "float16"

            // Manual on/off for the local engine. ON = model resident (instant
            // dictation, ~3 GB VRAM, keeps the laptop dGPU awake -> battery
            // cost); OFF = engine down (dGPU sleeps), dictation cold-starts or
            // routes to a cloud backend. A deliberate toggle, NOT an idle
            // timeout (an idle timeout that only unloads weights leaves the
            // CUDA context alive, so the dGPU never sleeps). Flippable via IPC.
            property bool resident: false
        }
    }

    property JsonObject cache: JsonObject {
        property bool enabled: true
        property int maxEntries: 10
        property bool deleteOnSuccess: true

        // Successful-transcription retention. When retainSuccessHours > 0, the
        // source audio (and a transcript sidecar) is copied to an on-disk
        // history dir on success instead of being lost when the tmpfs working
        // copy is cleaned. This is a safety net against silent truncation /
        // bad transcriptions (e.g. gpt-4o-transcribe cutting off long audio):
        // the original recording stays recoverable for a while. Set to 0 to
        // restore the old behaviour (delete-on-success, nothing retained).
        // maxSuccessEntries is a count backstop so a busy day can't fill disk
        // even before the age sweep runs. WAV at 16kHz mono is ~1.9 MB/min.
        property int retainSuccessHours: 24
        property int maxSuccessEntries: 50
    }

    // Audio ducking: lower the master sink volume while the mic is hot
    // (recording, not paused) so background audio contaminates the
    // transcription less. volume is ABSOLUTE: the sink is set to this level
    // while ducked (0 = full silence, 0.3 = 30%), unless it was already lower —
    // ducking never raises the volume. shell.json currently overrides this to 0;
    // see the diagnostic note in AudioDucking.qml for how a crash mid-duck then
    // presents.
    property JsonObject ducking: JsonObject {
        property bool enabled: true
        property real volume: 0.3
    }
}
