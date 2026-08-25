import qs.config
import qs.services
import qs.utils
import Quickshell
import Quickshell.Io
import Symmetria
import QtQuick

/// Per-session audio recording job: state machine, recording pipeline,
/// encoding, and clipboard copy.
///
/// Created dynamically by AudioRecorderService via Component.createObject().
///
/// State machine:
///   recording ⇄ paused → saving → success → [removed]
///                           ↓
///                         error → [removed]
QtObject {
    id: job

    // ── Public properties ──────────────────────────────────────────────

    /// Current state: "recording", "paused", "saving", "error", "success"
    readonly property string state: _state

    /// Audio level (0.0-1.0) during recording
    readonly property real audioLevel: _audioLevel

    /// Whether currently recording
    readonly property bool recording: _state === "recording"

    /// Elapsed recording time in seconds
    readonly property real elapsedSeconds: _currentElapsed

    /// Error detail properties
    readonly property string errorDetail: _errorDetail
    readonly property string errorHint: _errorHint

    /// Output file path (set after encoding succeeds)
    readonly property string outputFilePath: _outputFilePath

    /// Whether the job is closing (triggers fade animation)
    property bool closing: false

    /// Session identifier
    property string sessionId: ""

    // ── Signals ────────────────────────────────────────────────────────

    /// Emitted when job is done and should be removed after success delay
    signal finished

    // ── Config properties ──────────────────────────────────────────────

    readonly property string _levelMonitorScript: Qt.resolvedUrl("../scripts/stt-level-monitor.sh").toString().replace(/^file:\/\//, "")

    // Auto-hide delay constraints (ms)
    readonly property int _minAutoHideDelay: 500
    readonly property int _maxAutoHideDelay: 10000

    // ── Internal state ─────────────────────────────────────────────────

    property string _state: "idle"
    property real _audioLevel: 0.0

    // Error detail
    property string _errorDetail: ""
    property string _errorHint: ""

    // Elapsed time tracking
    property real _currentElapsed: 0
    property real _recordingStartTime: 0
    property real _accumulatedSeconds: 0

    // Segment management
    property int _segmentCounter: 0
    property list<string> _segmentFiles: []
    property string _outputFilePath: ""

    // Pending action for recordProcess.onExited callback
    property string _pendingRecordAction: ""

    // Current segment file path
    readonly property string _currentSegmentPath: {
        if (sessionId === "")
            return "";
        return `${AudioRecorderService._tempDir}/session_${sessionId}_segment_${_segmentCounter}.wav`;
    }

    // ── Public methods ─────────────────────────────────────────────────

    /// Stop recording and encode to OGG/Opus.
    function stop(): void {
        if (_state !== "recording" && _state !== "paused")
            return;
        console.log("[AudioRec] job.stop | id=" + sessionId + " segments=" + _segmentFiles.length);

        if (_state === "paused") {
            _startEncoding();
            return;
        }

        _pendingRecordAction = "submit";
        levelMonitorProcess.running = false;
        recordProcess.running = false;
    }

    /// Pause if recording.
    function pause(): void {
        if (_state !== "recording")
            return;
        _pendingRecordAction = "pause";
        levelMonitorProcess.running = false;
        recordProcess.running = false;
    }

    /// Resume from pause.
    function resume(): void {
        if (_state !== "paused")
            return;
        _segmentCounter++;
        _startRecording();
        _state = "recording";
    }

    /// Cancel: kill processes, discard audio, remove.
    function cancel(): void {
        _pendingRecordAction = "cancel";
        _stopAllTimers();

        if (recordProcess.running)
            recordProcess.signal(9);
        if (levelMonitorProcess.running)
            levelMonitorProcess.running = false;
        if (encodeProcess.running)
            encodeProcess.signal(9);

        _cleanupTempFiles();
        AudioRecorderService._removeJob(job);
    }

    // ── Internal methods ───────────────────────────────────────────────

    function _startRecording(): void {
        const segmentPath = _currentSegmentPath;
        const sampleRate = Config.audioRecorder?.sampleRate ?? 48000;
        const channels = Config.audioRecorder?.channels ?? 2;

        recordProcess.capturedSegmentPath = segmentPath;
        recordProcess.command = ["pw-record", "--format=s16", `--rate=${sampleRate}`, `--channels=${channels}`, segmentPath];
        recordProcess.running = true;
        levelMonitorProcess.running = true;
    }

    function _startEncoding(): void {
        _state = "saving";

        if (_segmentFiles.length === 0) {
            _setErrorState("No audio segments", "Recording may have failed");
            return;
        }

        const timestamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss");
        _outputFilePath = `${AudioRecorderService._outputDir}/recording_${timestamp}.ogg`;
        const bitrate = (Config.audioRecorder?.bitrate ?? 192) + "k";

        if (_segmentFiles.length === 1) {
            encodeProcess.command = ["ffmpeg", "-i", _segmentFiles[0], "-c:a", "libopus", "-b:a", bitrate, "-y", _outputFilePath];
        } else {
            const args = ["ffmpeg"];
            for (const f of _segmentFiles) {
                args.push("-i", f);
            }
            let filterInputs = "";
            for (let i = 0; i < _segmentFiles.length; i++)
                filterInputs += `[${i}:a]`;
            args.push("-filter_complex", `${filterInputs}concat=n=${_segmentFiles.length}:v=0:a=1[out]`, "-map", "[out]", "-c:a", "libopus", "-b:a", bitrate, "-y", _outputFilePath);
            encodeProcess.command = args;
        }

        console.log("[AudioRec] encoding | id=" + sessionId + " segments=" + _segmentFiles.length + " → " + _outputFilePath);
        encodeProcess.running = true;
    }

    function _setErrorState(detail: string, hint: string): void {
        _errorDetail = detail;
        _errorHint = hint;
        _state = "error";
        Toaster.toast(qsTr("Audio: %1").arg(detail), hint, "error", Toast.Error);
    }

    function _cleanupTempFiles(): void {
        if (sessionId !== "") {
            Quickshell.execDetached(["find", AudioRecorderService._tempDir, "-maxdepth", "1", "-name", `session_${sessionId}_*`, "-delete"]);
        }
    }

    function _stopAllTimers(): void {
        elapsedTimer.stop();
        successTimer.stop();
        _removalTimer.stop();
    }

    /// Trigger animated removal.
    function startRemoval(): void {
        _removalTimer.start();
    }

    /// Cleanup for Component.onDestruction (called by service shutdown)
    function _destroyCleanup(): void {
        _stopAllTimers();
        if (sessionId !== "")
            _cleanupTempFiles();
        if (recordProcess.running)
            recordProcess.signal(9);
        if (levelMonitorProcess.running)
            levelMonitorProcess.running = false;
        if (encodeProcess.running)
            encodeProcess.signal(9);
        if (clipboardProcess.running)
            clipboardProcess.running = false;
    }

    // ── State change handlers ──────────────────────────────────────────

    on_StateChanged: {
        if (_state === "recording") {
            if (_recordingStartTime === 0) {
                _recordingStartTime = Date.now();
                _currentElapsed = _accumulatedSeconds;
            }
        } else if (_state === "saving") {
            _recordingStartTime = 0;
        }

        if (_state === "success") {
            successTimer.start();
        } else {
            successTimer.stop();
        }
    }

    onRecordingChanged: {
        if (!recording)
            _audioLevel = 0.0;
    }

    // ── Timers ─────────────────────────────────────────────────────────

    readonly property Timer elapsedTimer: Timer {
        interval: 250
        repeat: true
        running: job.recording
        onTriggered: {
            if (job._recordingStartTime > 0)
                job._currentElapsed = job._accumulatedSeconds + (Date.now() - job._recordingStartTime) / 1000;
        }
    }

    readonly property Timer successTimer: Timer {
        interval: {
            const delay = Config.audioRecorder?.autoHideDelay ?? 1500;
            return Math.max(job._minAutoHideDelay, Math.min(job._maxAutoHideDelay, delay));
        }
        onTriggered: {
            if (job._state === "success")
                job.finished();
        }
    }

    readonly property Timer _removalTimer: Timer {
        interval: Appearance.anim.durations.normal + 50
        onTriggered: AudioRecorderService._finalizeRemoval(job)
    }

    // ── Processes ──────────────────────────────────────────────────────

    readonly property Process recordProcess: Process {
        property string capturedSegmentPath: ""
        onExited: (code, status) => {
            const action = job._pendingRecordAction;
            job._pendingRecordAction = "";
            console.log("[AudioRec] recordProcess.onExited | id:", job.sessionId, "| code:", code, "| action:", action || "(none)");

            if (action === "cancel")
                return;

            // Register completed segment
            const segPath = capturedSegmentPath;
            if (segPath !== "") {
                const files = job._segmentFiles.slice();
                files.push(segPath);
                job._segmentFiles = files;
            }

            if (action === "pause") {
                if (job._recordingStartTime > 0) {
                    job._accumulatedSeconds += (Date.now() - job._recordingStartTime) / 1000;
                    job._recordingStartTime = 0;
                }
                job._audioLevel = 0.0;
                job._state = "paused";
            } else if (action === "submit") {
                if (job._recordingStartTime > 0) {
                    job._accumulatedSeconds += (Date.now() - job._recordingStartTime) / 1000;
                    job._currentElapsed = job._accumulatedSeconds;
                    job._recordingStartTime = 0;
                }
                job._audioLevel = 0.0;
                job._startEncoding();
            } else if (code !== 0 && job._state === "recording") {
                job._setErrorState("Recording failed", "Check audio device");
            }
        }
    }

    readonly property Process levelMonitorProcess: Process {
        command: [job._levelMonitorScript]
        stdout: SplitParser {
            onRead: data => {
                const level = parseFloat(data.trim());
                if (!isNaN(level) && isFinite(level))
                    job._audioLevel = Math.min(1.0, Math.max(0.0, level));
            }
        }
    }

    readonly property Process encodeProcess: Process {
        onExited: (code, status) => {
            console.log("[AudioRec] encodeProcess.onExited | id:", job.sessionId, "| code:", code);
            if (job._state !== "saving")
                return;

            if (code === 0) {
                clipboardProcess.command = ["wl-copy", job._outputFilePath];
                clipboardProcess.running = true;
            } else {
                job._setErrorState("Encoding failed", "Is ffmpeg with libopus installed?");
            }
        }
    }

    readonly property Process clipboardProcess: Process {
        onExited: (code, status) => {
            job._state = "success";
            job._cleanupTempFiles();
            Toaster.toast(qsTr("Audio recorded"), qsTr("Saved: %1").arg(job._outputFilePath.split("/").pop()), "mic", Toast.Success);
        }
    }
}
