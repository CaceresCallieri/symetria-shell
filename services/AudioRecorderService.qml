pragma Singleton

import qs.config
import qs.services
import qs.utils
import Quickshell
import Quickshell.Io
import QtQuick

/// Audio recorder service — singleton orchestrator for a single recording job.
///
/// Records audio via pw-record (48kHz stereo WAV segments), encodes to
/// OGG/Opus via ffmpeg on stop, saves to ~/Audio/, and copies the file
/// path to clipboard.
///
/// State machine per job (see AudioRecorderJob.qml):
///   recording ⇄ paused → saving → success → [removed]
///                           ↓
///                         error → [removed]
Singleton {
    id: root

    // ─────────────────────────────────────────────────────────────────────────
    // Public interface
    // ─────────────────────────────────────────────────────────────────────────

    /// Whether a job exists (controls drawer visibility)
    readonly property bool active: _job !== null

    /// The current job, or null
    readonly property AudioRecorderJob job: _job

    /// Emitted when an action is successfully dispatched.
    signal actionTriggered(string action)

    // ─────────────────────────────────────────────────────────────────────────
    // Internal state
    // ─────────────────────────────────────────────────────────────────────────

    property AudioRecorderJob _job: null
    property real _lastToggleTime: 0
    readonly property int _toggleDebounceMs: 200
    property bool _tempDirReady: false
    property bool _outputDirReady: false

    readonly property string _runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string _tempDir: `${_runtimeDir}/symmetria-audio-recorder`
    readonly property string _outputDir: {
        const custom = Config.audioRecorder?.outputDir ?? "";
        if (custom !== "")
            return custom;
        return Quickshell.env("HOME") + "/Audio";
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Orchestrator commands
    // ─────────────────────────────────────────────────────────────────────────

    /// Toggle: start if idle, stop if recording/paused, cancel if error.
    function toggle(): void {
        const now = Date.now();
        if (now - _lastToggleTime < _toggleDebounceMs)
            return;
        _lastToggleTime = now;

        if (!_job) {
            start();
        } else if (_job.state === "recording" || _job.state === "paused") {
            stop();
        } else if (_job.state === "error") {
            cancel();
        }
        // If saving or success, ignore toggle (job is finishing)
    }

    /// Start a new recording.
    function start(): void {
        if (_job) {
            console.warn("[AudioRec] start() called while job active — ignoring");
            return;
        }

        _job = _createJob();
        _job._state = "recording";

        // Ensure both directories exist before recording
        if (_tempDirReady && _outputDirReady) {
            _job._startRecording();
        } else {
            tempDirProcess.running = true;
        }
    }

    /// Stop the active recording and encode.
    function stop(): void {
        if (!_job)
            return;
        actionTriggered("stop");
        _job.stop();
    }

    /// Toggle pause on the active recording.
    function pause(): void {
        if (!_job)
            return;
        if (_job._state === "recording") {
            actionTriggered("pause");
            _job.pause();
        } else if (_job._state === "paused") {
            actionTriggered("resume");
            _job.resume();
        }
    }

    /// Cancel: kill and discard.
    function cancel(): void {
        if (!_job)
            return;
        actionTriggered("cancel");
        _job.cancel();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Job lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    Component {
        id: jobComponent
        AudioRecorderJob {}
    }

    function _createJob(): AudioRecorderJob {
        const job = jobComponent.createObject(root, {
            sessionId: Date.now().toString()
        });
        job.finished.connect(() => _onJobFinished(job));
        return job;
    }

    function _removeJob(job: AudioRecorderJob): void {
        job.closing = true;
        job.startRemoval();
    }

    function _onJobFinished(job: AudioRecorderJob): void {
        _removeJob(job);
    }

    function _finalizeRemoval(job: AudioRecorderJob): void {
        if (_job === job)
            _job = null;
        job.destroy();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Service-level processes
    // ─────────────────────────────────────────────────────────────────────────

    // Ensure both temp and output directories exist before first recording
    Process {
        id: tempDirProcess
        command: ["mkdir", "-p", root._tempDir, root._outputDir]
        onExited: (code, status) => {
            if (code !== 0) {
                console.error("[AudioRec] Failed to create directories");
                if (root._job)
                    root._job._setErrorState("Failed to create directories", "Check permissions on ~/Audio/");
                return;
            }
            root._tempDirReady = true;
            root._outputDirReady = true;
            if (root._job && root._job._state === "recording")
                root._job._startRecording();
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Cleanup
    // ─────────────────────────────────────────────────────────────────────────

    Component.onDestruction: {
        if (_job) {
            _job._destroyCleanup();
        }
    }
}
