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

    property int autoHideDelay: 1500
    property int processingTimeout: 120000
    // Valid values: "clipboard" | "inject" | "submit" | "ask"
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
    // while ducked (0.3 = 30%), unless it was already lower — ducking never
    // raises the volume.
    property JsonObject ducking: JsonObject {
        property bool enabled: true
        property real volume: 0.3
    }
}
