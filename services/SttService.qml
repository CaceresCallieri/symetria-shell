pragma Singleton

import qs.config
import qs.services
import qs.utils
import Quickshell
import Quickshell.Io
import Symmetria
import QtQuick

/// Native speech-to-text service with pipeline queue support.
///
/// Orchestrates up to 3 concurrent SttJob instances. At most one job can be
/// in "recording" state; the rest process in the background.
///
/// Pipeline per job: pw-record → WAV file → curl (OpenAI API) → wl-copy [→ sendshortcut inject]
///
/// Job state machine (see SttJob.qml):
///   recording ⇄ paused → processing → transcribed → delivering → success → [removed]
///                            ↓             ↓
///                          error ──retry──→ processing
///                                ╰─auto-retry─╯ (silent, ≤_maxAutoRetries times)
Singleton {
    id: root

    // ─────────────────────────────────────────────────────────────────────────
    // Public interface
    // ─────────────────────────────────────────────────────────────────────────

    /// Whether any jobs exist (controls drawer visibility)
    readonly property bool active: _jobs.length > 0

    /// The job list — newest first. Bound by Wrapper's Repeater.
    // intentional var: JS array rebuilt atomically with spread operator for O(1) binding triggers
    readonly property var jobs: _jobs

    /// The currently recording job (at most one), or null
    readonly property SttJob activeRecording: _activeRecording

    /// Whether the delivery mode radio toggle should be shown (from config)
    readonly property bool isAskMode: _deliveryMode === "ask"


    /// Emitted when an action is successfully dispatched.
    /// Used by Content.qml to animate the corresponding control button.
    /// sessionId scopes the action to the correct job card in multi-job scenarios.
    /// Empty sessionId means "broadcast to all" (used for service-level actions).
    signal actionTriggered(string sessionId, string action)

    // ─────────────────────────────────────────────────────────────────────────
    // Shared state (service-level, not per-job)
    // ─────────────────────────────────────────────────────────────────────────

    // intentional var: JS array with spread/filter reassignment — [job, ..._jobs] pattern
    property var _jobs: []
    property SttJob _activeRecording: null
    readonly property int _maxJobs: 3

    // Toggle debouncing
    property real _lastToggleTime: 0
    readonly property int _toggleDebounceMs: 200

    // Runtime delivery choice for "ask" mode.
    // Persists across recordings within the same shell session.
    property string _lastDeliveryChoice: "submit"

    // Temp directory readiness
    property bool _tempDirReady: false

    // FIFO delivery queues: windowAddress → [SttJob, ...]
    // intentional var: JS object used as hash map ({ windowAddress: SttJob[] })
    property var _deliveryQueues: ({})

    // Per-session vocabulary hints (tag-chip widget).
    // Service-level so the widget and IPC can modify them without job reference.
    // Reset after each transcription completes (when _activeRecording → null).
    // intentional var: JS array modified via spread/filter/some — requires JS array semantics
    property var _sessionVocabHints: []
    property bool vocabHintsVisible: false
    // intentional var: public alias for JS array property above
    readonly property var sessionVocabHints: _sessionVocabHints

    // Directories
    readonly property string _runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string _tempDir: `${_runtimeDir}/symmetria-stt`

    // Delivery mode from config: "clipboard" (default), "inject", "submit", or "ask"
    readonly property string _deliveryMode: {
        const mode = Config.stt?.deliveryMode ?? "clipboard";
        if (mode === "inject" || mode === "submit" || mode === "ask") return mode;
        return "clipboard";
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Orchestrator commands
    // ─────────────────────────────────────────────────────────────────────────

    /// Toggle: start if idle, submit if recording, retry if most recent is error.
    function toggle(): void {
        const now = Date.now();
        if (now - _lastToggleTime < _toggleDebounceMs) {
            console.log("[STT:D19] toggle() DEBOUNCED | elapsed:", now - _lastToggleTime, "ms");
            return;
        }
        Logger.log("qml", "stt", "toggle | activeRecording=" + (_activeRecording !== null) + " jobs=" + _jobs.length);

        if (_activeRecording) {
            _lastToggleTime = now;
            stop();
        } else if (_jobs.length === 0) {
            _lastToggleTime = now;
            start();
        } else {
            // Jobs exist but none recording — check for errors
            const errorJob = _mostRecentErrorJob();
            if (errorJob) {
                _lastToggleTime = now;
                errorJob.retry();
                actionTriggered(errorJob.sessionId, "retry");
            } else if (_jobs.length < _maxJobs) {
                _lastToggleTime = now;
                start();
            }
        }
    }

    /// Start a new recording job.
    function start(): void {
        if (_activeRecording) {
            console.warn("[STT] start() called while already recording — ignoring");
            return;
        }
        if (_jobs.length >= _maxJobs) {
            Toaster.toast(
                qsTr("STT: Max recordings reached"),
                qsTr("Wait for a job to finish (max %1)").arg(_maxJobs),
                "",
                Toast.Warning
            );
            return;
        }
        Logger.log("qml", "stt", "start | delivery=" + _deliveryMode + " jobs=" + _jobs.length);

        // Check API key before starting (SttJob._resolvedApiKey checks
        // both Config.stt.apiKey and OPENAI_API_KEY env var)
        const job = _createJob();
        if (job._resolvedApiKey === "") {
            job._setErrorState("config", "API key not configured",
                "Set OPENAI_API_KEY env var or stt.apiKey in shell.json");
            _jobs = [job, ..._jobs];
            return;
        }

        // Capture target window and resolve agent data synchronously.
        job._captureTargetWindow();
        job._resolveAgentTarget();
        Logger.log("qml", "stt", "session | id=" + job.sessionId + " target=" + job._targetWindowAddress + " class=" + job._targetWindowClass);

        _activeRecording = job;
        job._state = "recording";

        // Add to _jobs AFTER state is "recording" so Repeater delegates
        // see FadeTransitions as visible from the first frame.
        _jobs = [job, ..._jobs];

        // Ensure temp dir exists, then start recording
        if (_tempDirReady) {
            job._startRecording();
        } else {
            tempDirProcess.running = true;
        }
    }

    /// Stop the active recording and submit for transcription.
    function stop(): void {
        if (!_activeRecording) return;
        actionTriggered(_activeRecording.sessionId, "stop");
        // Snapshot session hints onto the job before clearing service-level state.
        // The recording→stop path is async (recordProcess.onExited calls
        // _startTranscription later), so _sessionVocabHints would be empty
        // by the time transcription starts without this snapshot.
        _activeRecording._snapshotVocabHints = _sessionVocabHints.slice();
        _activeRecording.stop();
        _activeRecording = null;
        _sessionVocabHints = [];
        vocabHintsVisible = false;
    }

    /// Toggle pause on the active recording.
    function pause(): void {
        if (!_activeRecording) return;
        if (_activeRecording._state === "recording") {
            actionTriggered(_activeRecording.sessionId, "pause");
            _activeRecording.pause();
        } else if (_activeRecording._state === "paused") {
            actionTriggered(_activeRecording.sessionId, "resume");
            _activeRecording.resume();
        }
    }

    /// Resume the active recording.
    function resume(): void {
        if (!_activeRecording) return;
        _activeRecording.resume();
    }

    /// Cancel the active recording (discard audio).
    function cancel(): void {
        const sid = _activeRecording?.sessionId ?? "";
        actionTriggered(sid, "cancel");
        if (_activeRecording) {
            const job = _activeRecording;
            _activeRecording = null;
            _sessionVocabHints = [];
            vocabHintsVisible = false;
            job.cancel();
        }
    }

    /// Restart: cancel active recording + start a new one.
    /// No-op if there is no active recording.
    function restart(): void {
        if (!_activeRecording) return;
        actionTriggered(_activeRecording.sessionId, "restart");
        restartDelayTimer.stop();
        const job = _activeRecording;
        _activeRecording = null;
        _sessionVocabHints = [];
        vocabHintsVisible = false;
        job.cancel();
        restartDelayTimer.start();
    }

    /// Retry the most recent errored job.
    function retry(): void {
        const errorJob = _mostRecentErrorJob();
        if (!errorJob) return;
        actionTriggered(errorJob.sessionId, "retry");
        errorJob.retry();
    }

    /// Switch the runtime delivery choice (only effective in "ask" mode).
    /// Applies to the active recording job.
    function setDeliveryChoice(mode: string): void {
        if (_deliveryMode !== "ask") {
            console.debug("[STT] setDeliveryChoice() ignored: deliveryMode is", _deliveryMode, "(not ask)");
            return;
        }
        if (mode !== "clipboard" && mode !== "inject" && mode !== "submit") return;
        if (_lastDeliveryChoice === mode) return;
        _lastDeliveryChoice = mode;
        if (_activeRecording)
            _activeRecording._activeDeliveryChoice = mode;
        actionTriggered(_activeRecording?.sessionId ?? "", "mode-" + mode);
    }

    /// Add a per-session vocabulary hint (shown as chip in the widget).
    function addSessionHint(word: string): void {
        const trimmed = word.trim();
        if (trimmed === "") return;
        if (_sessionVocabHints.some(h => h.toLowerCase() === trimmed.toLowerCase())) return;
        _sessionVocabHints = [..._sessionVocabHints, trimmed];
    }

    /// Remove a per-session vocabulary hint by index.
    function removeSessionHint(index: int): void {
        _sessionVocabHints = _sessionVocabHints.filter((_, i) => i !== index);
    }

    /// Toggle the vocabulary hints widget (only during active recording).
    function toggleVocabHints(): void {
        if (!_activeRecording) return;
        vocabHintsVisible = !vocabHintsVisible;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers (service-level)
    // ─────────────────────────────────────────────────────────────────────────

    function _mostRecentErrorJob(): SttJob {
        for (const job of _jobs) {
            if (job.state === "error" && job.errorSource !== "config") return job;
        }
        return null;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Job lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    Component { id: jobComponent; SttJob {} }

    function _createJob(): SttJob {
        const job = jobComponent.createObject(root, {
            sessionId: Date.now().toString(),
            _activeDeliveryChoice: _lastDeliveryChoice
        });

        job.finished.connect(() => _onJobFinished(job));
        job.readyForDelivery.connect(() => _enqueueForDelivery(job));

        // Caller must add to _jobs AFTER setting job state, so that
        // Repeater delegates see the correct state at creation time.
        return job;
    }

    function _removeJob(job: SttJob): void {
        job.closing = true;  // triggers slide-up animation in delegate
        job.startRemoval();  // per-job timer, avoids overwrite race
    }

    function _onJobFinished(job: SttJob): void {
        // Job reported success and its successTimer fired — remove it
        _removeJob(job);
    }

    function _finalizeRemoval(job: SttJob): void {
        _jobs = _jobs.filter(j => j !== job);
        job.destroy();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FIFO delivery
    // ─────────────────────────────────────────────────────────────────────────

    function _enqueueForDelivery(job: SttJob): void {
        const key = job._targetWindowAddress || "__clipboard__";
        const queues = _deliveryQueues;
        if (!queues[key]) queues[key] = [];
        queues[key].push(job);
        _deliveryQueues = queues;  // reassign to emit changed (var mutation is silent)
        _tryDeliverNext(key);
    }

    function _tryDeliverNext(key: string): void {
        const queues = _deliveryQueues;
        const queue = queues[key];
        if (!queue || queue.length === 0) return;

        const front = queue[0];
        if (front.state !== "transcribed") return;  // not ready or already delivering

        front._startDeliveryChain();
    }

    function _onDeliveryComplete(job: SttJob): void {
        const key = job._targetWindowAddress || "__clipboard__";
        const queues = _deliveryQueues;
        const queue = queues[key];
        if (queue && queue.length > 0 && queue[0] === job) {
            queue.shift();
            _deliveryQueues = queues;  // reassign to emit changed (var mutation is silent)
            _tryDeliverNext(key);  // pump next
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Service-level timers & processes
    // ─────────────────────────────────────────────────────────────────────────

    // Delayed start after cancel (used by restart)
    Timer {
        id: restartDelayTimer
        interval: 500
        onTriggered: root.start()
    }

    // Ensure temp directory exists before first recording
    Process {
        id: tempDirProcess
        command: ["mkdir", "-p", root._tempDir]
        onExited: (code, status) => {
            if (code !== 0) {
                console.error("[STT] Failed to create temp directory:", root._tempDir);
                if (root._activeRecording)
                    root._activeRecording._setErrorState("internal", "Failed to create temp directory", "Check permissions");
                return;
            }
            root._tempDirReady = true;
            if (root._activeRecording && root._activeRecording._state === "recording")
                root._activeRecording._startRecording();
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Cleanup
    // ─────────────────────────────────────────────────────────────────────────

    Component.onDestruction: {
        restartDelayTimer.stop();
        for (const job of _jobs) {
            job._destroyCleanup();
        }
    }
}
