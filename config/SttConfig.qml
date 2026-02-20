import Quickshell.Io

JsonObject {
    property bool enabled: true
    property string apiKey: ""
    property string backend: "openai"
    property string model: "gpt-4o-transcribe"
    property int autoHideDelay: 1500
    property int processingTimeout: 120000
    property string deliveryMode: "clipboard"

    property JsonObject recording: JsonObject {
        property string format: "wav"
        property int sampleRate: 16000
        property int channels: 1
    }

    property JsonObject cache: JsonObject {
        property bool enabled: true
        property int maxEntries: 10
        property bool deleteOnSuccess: true
    }
}
