import qs.config
import qs.services
import qs.utils
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Symmetria
import QtQuick

/// Per-session STT job: state machine, recording pipeline, transcription,
/// delivery chain, error handling, and auto-retry.
///
/// Created dynamically by SttService via Component.createObject().
/// Accesses service-level state (delivery queues, delivery mode, temp dir)
/// through the SttService singleton.
///
/// State machine:
///   recording ⇄ paused → processing → transcribed → delivering → success → [removed]
///                            ↓             ↓
///                          error ──retry──→ processing
///                                ╰─auto-retry─╯ (silent, ≤_maxAutoRetries times)
QtObject {
    id: job

    // ── Public properties ──────────────────────────────────────────────

    /// Current state: "idle", "recording", "paused", "processing", "transcribed",
    ///   "delivering", "error", "success"
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
    readonly property string errorRaw: _errorRaw
    readonly property string errorSource: _errorSource

    /// Transcribed text result
    readonly property string transcribedText: _transcribedText

    /// The user's runtime delivery choice for this job
    readonly property string activeDeliveryChoice: _activeDeliveryChoice

    /// Injection delivery path
    readonly property string injectionPath: _injectionPath

    /// Whether submit was downgraded
    readonly property bool injectionDowngraded: _injectionDowngraded

    /// Whether RPC confirmed Enter was sent
    readonly property bool injectionSubmitted: _injectionSubmitted

    /// Whether this job is currently in an auto-retry cycle
    readonly property bool autoRetrying: _autoRetryCount > 0 && _state === "processing"

    /// Whether the job is closing (triggers fade animation)
    property bool closing: false

    /// Session identifier
    property string sessionId: ""

    // ── Signals ───────────────────────────────────��────────────────────

    /// Emitted when job is done and should be removed after success delay
    signal finished()

    /// Emitted when transcription succeeds and job is ready for delivery
    signal readyForDelivery()

    // ── Config properties (only used within the job) ───────────────────

    // Script paths (resolved relative to project root)
    readonly property string _levelMonitorScript: Qt.resolvedUrl("../scripts/stt-level-monitor.sh").toString().replace(/^file:\/\//, "")
    readonly property string _transcribeScript: Qt.resolvedUrl("../scripts/stt-transcribe.sh").toString().replace(/^file:\/\//, "")
    readonly property string _injectScript: Qt.resolvedUrl("../scripts/stt-inject.sh").toString().replace(/^file:\/\//, "")

    // API key: config value takes priority, then environment variable
    readonly property string _resolvedApiKey: {
        const configKey = Config.stt?.apiKey ?? "";
        if (configKey !== "") return configKey;
        return Quickshell.env("OPENAI_API_KEY") || "";
    }

    // Auto-hide delay constraints (ms)
    readonly property int _minAutoHideDelay: 500
    readonly property int _maxAutoHideDelay: 10000

    // ── Internal state ─────────────────────────────────────────────────

    property string _state: "idle"
    property real _audioLevel: 0.0
    property string _transcribedText: ""

    // Error detail properties
    property string _errorDetail: ""
    property string _errorHint: ""
    property string _errorSource: ""
    property string _errorRaw: ""

    // Auto-retry for transient errors (network, 5xx, timeout)
    property int _autoRetryCount: 0
    readonly property int _maxAutoRetries: 2
    readonly property int _autoRetryDelayMs: 2000  // backoff before retrying transient failures

    // Elapsed time tracking
    property real _currentElapsed: 0
    property real _recordingStartTime: 0
    property real _accumulatedSeconds: 0

    // Segment management
    property int _segmentCounter: 0
    property list<string> _segmentFiles: []
    property string _currentAudioFile: ""

    // Target window for inject delivery (captured at start-time)
    property string _targetWindowAddress: ""
    property string _targetWindowClass: ""
    property int _targetWindowPid: -1
    // Target Neovim socket (resolved from AgentService at start-time)
    property string _targetNvimSocket: ""
    property int _targetNvimActiveBuf: -1

    // Pending action for recordProcess.onExited callback
    property string _pendingRecordAction: ""
    // Set to true when processingTimeoutTimer kills transcribeProcess,
    // so transcribeProcess.onExited can skip duplicate error handling.
    property bool _pendingTimeoutKill: false

    // Vocabulary hints snapshot: populated by SttService.stop() before
    // clearing _sessionVocabHints, so the async recordProcess.onExited
    // path still has access to the hints at transcription time.
    property list<string> _snapshotVocabHints: []

    // Runtime delivery choice for "ask" mode (inherited from service, locked on submit)
    property string _activeDeliveryChoice: "clipboard"

    // Injection result feedback
    property string _injectionPath: ""
    property bool _injectionDowngraded: false
    property bool _injectionSubmitted: false

    // Current segment file path
    readonly property string _currentSegmentPath: {
        if (sessionId === "") return "";
        return `${SttService._tempDir}/session_${sessionId}_segment_${_segmentCounter}.wav`;
    }

    // ── Public methods ─────────────────────────────────────────────────

    /// Stop recording and submit for transcription.
    function stop(): void {
        if (_state !== "recording" && _state !== "paused") return;
        Logger.log("qml", "stt", "job.stop | id=" + sessionId + " segments=" + _segmentFiles.length);

        console.log("[STT:D02] job.stop() | target:", _targetWindowAddress,
            "| class:", _targetWindowClass,
            "| nvimSocket:", _targetNvimSocket,
            "| buf:", _targetNvimActiveBuf);

        if (_state === "paused") {
            console.log("[STT:D03] paused path → direct _submitForTranscription()");
            _submitForTranscription();
            return;
        }

        // Stop recording first, then submit on exit
        console.log("[STT:D03] recording path → SIGTERM pw-record, pending submit");
        _pendingRecordAction = "submit";
        levelMonitorProcess.running = false;
        recordProcess.running = false;
    }

    /// Pause if recording.
    function pause(): void {
        if (_state !== "recording") return;
        _pendingRecordAction = "pause";
        levelMonitorProcess.running = false;
        recordProcess.running = false;
    }

    /// Resume from pause.
    function resume(): void {
        if (_state !== "paused") return;
        _segmentCounter++;
        _startRecording();
        // Assign _state last so on_StateChanged fires with _recordingStartTime
        // still 0, matching the start() path. The handler initializes it.
        _state = "recording";
    }

    /// Cancel: kill processes, discard audio, remove from queue.
    function cancel(): void {
        _pendingRecordAction = "cancel";
        _stopAllTimers();

        if (recordProcess.running) recordProcess.signal(9);
        if (levelMonitorProcess.running) levelMonitorProcess.running = false;
        if (transcribeProcess.running) transcribeProcess.signal(9);
        if (concatProcess.running) concatProcess.signal(9);

        _cleanupTempFiles();
        _clearSttTargetIfOwned();

        // Clear activeRecording if this job is the active one
        if (SttService._activeRecording === job)
            SttService._activeRecording = null;

        // Remove from delivery queue if enqueued
        const key = _targetWindowAddress || "__clipboard__";
        const queues = SttService._deliveryQueues;
        const queue = queues[key];
        if (queue) {
            const idx = queue.indexOf(job);
            if (idx >= 0) {
                const wasDelivering = _state === "delivering";
                queue.splice(idx, 1);
                SttService._deliveryQueues = queues;  // reassign to emit changed (var mutation is silent)
                if (wasDelivering) SttService._tryDeliverNext(key);
            }
        }

        // Remove from jobs list (via _removeJob so hide animation plays)
        SttService._removeJob(job);
    }

    /// Retry failed transcription with the same audio file.
    function retry(): void {
        if (_state !== "error") return;
        Logger.log("qml", "stt", "job.retry | id=" + sessionId);

        if (_currentAudioFile === "") {
            _setErrorState("internal", "No audio file to retry", "Start a new recording", false);
            return;
        }

        autoRetryTimer.stop();
        _autoRetryCount = 0;  // manual retry resets the auto-retry budget
        _clearErrorState();
        _transcribedText = "";
        _state = "processing";
        _startTranscription(_currentAudioFile);
    }

    /// Switch the delivery choice (only meaningful in "ask" mode during recording).
    /// Direct-UI entry point: does NOT emit actionTriggered.
    /// For IPC callers, use SttService.setDeliveryChoice() which emits the signal.
    function setDeliveryChoice(mode: string): void {
        if (SttService._deliveryMode !== "ask") return;
        if (mode !== "clipboard" && mode !== "inject" && mode !== "submit") return;
        if (_activeDeliveryChoice === mode) return;
        _activeDeliveryChoice = mode;
        SttService._lastDeliveryChoice = mode;
    }

    // ── Internal methods ───────────────────────────────────────────────

    function _setErrorState(source: string, detail: string, hint: string, silent: bool): void {
        _errorSource = source;
        _errorDetail = detail;
        _errorHint = hint;
        _state = "error";
        if (!silent)
            Toaster.toast(qsTr("STT: %1").arg(detail), hint, "error", Toast.Error);
        if (sessionId !== "" && _segmentFiles.length > 0 && _currentAudioFile !== "") {
            const toRemove = _segmentFiles.filter(s => s !== _currentAudioFile);
            if (toRemove.length > 0)
                Quickshell.execDetached(["rm", "-f", ...toRemove]);
        }
    }

    function _clearErrorState(): void {
        _errorSource = "";
        _errorDetail = "";
        _errorHint = "";
        _errorRaw = "";
    }

    /// Capture the currently active window for inject delivery.
    function _captureTargetWindow(): void {
        if (SttService._deliveryMode === "clipboard") {
            console.log("[STT:D04] _captureTargetWindow() skipped — deliveryMode is clipboard");
            return;
        }
        // Prefer Hypr.activeToplevel (filtered by wayland activation), but fall back
        // to raw Hyprland.activeToplevel for fresh shell instances where the Wayland
        // activation event hasn't arrived yet. STT only needs the Hyprland-reported
        // window identity (address, class, pid), not Wayland activation state.
        const toplevel = Hypr.activeToplevel ?? Hyprland.activeToplevel;
        if (toplevel) {
            _targetWindowAddress = `0x${toplevel.address}`;
            _targetWindowClass = toplevel.lastIpcObject?.class ?? "";
            _targetWindowPid = toplevel.lastIpcObject?.pid ?? -1;
            console.log("[STT:D04] _captureTargetWindow() captured | address:", _targetWindowAddress,
                "| class:", _targetWindowClass, "| pid:", _targetWindowPid);
        } else {
            console.warn("[STT:D04] _captureTargetWindow() — NO activeToplevel!");
        }
    }

    /// Clear the AgentService STT target highlight if this job is the current owner.
    function _clearSttTargetIfOwned(): void {
        if (_targetWindowPid > 0 &&
            AgentService.sttTargetTerminalPid === _targetWindowPid &&
            AgentService.sttTargetBufId === _targetNvimActiveBuf) {
            AgentService.clearSttTarget();
        }
    }

    /// Resolve agent data from AgentService using captured terminal PID.
    function _resolveAgentTarget(): void {
        _targetNvimSocket = "";
        _targetNvimActiveBuf = -1;

        if (!AgentService.bridgeRunning) return;

        const agent = AgentService.activeAgentForTerminal(_targetWindowPid);
        if (!agent) return;

        _targetNvimSocket = AgentService.nvimSocketForAgent(agent);
        _targetNvimActiveBuf = agent.buf ?? -1;
        Logger.log("qml", "stt", "agent-target | buf=" + agent.buf + " socket=" + _targetNvimSocket);

        const effectiveMode = SttService._deliveryMode === "ask" ? _activeDeliveryChoice : SttService._deliveryMode;
        if (effectiveMode !== "clipboard") {
            AgentService.setSttTarget(_targetWindowPid, agent.buf ?? -1);
        }
    }

    /// Categorize API errors from stt-transcribe.sh stderr output.
    function _categorizeApiError(stderrText: string): void {
        _errorRaw = stderrText;

        const patterns = [
            { re: /ERROR:401/,     detail: "Authentication failed",   hint: "Check your API key" },
            { re: /ERROR:429/,     detail: "Quota exceeded",          hint: "Check your API plan limits" },
            { re: /ERROR:5\d\d/,   detail: "API server error",        hint: "Try again later" },
            { re: /Network error/, detail: "Network error",           hint: "Check your connection" },
            { re: /timed out/i,    detail: "Connection timed out",    hint: "Check your network" },
            { re: /Missing/,       detail: "Configuration error",     hint: "Check STT settings" },
        ];

        for (const p of patterns) {
            if (p.re.test(stderrText)) {
                _errorDetail = p.detail;
                _errorHint = p.hint;
                return;
            }
        }

        _errorDetail = "Transcription failed";
        _errorHint = "Check logs for details";
    }

    /// Whether the current error is transient and safe to auto-retry.
    function _isTransientError(): bool {
        if (_errorSource === "timeout") return true;
        if (_errorSource !== "api") return false;
        // Network failures, server errors, and generic failures are transient.
        // Auth (401) and quota (429) are permanent — user must fix config/plan.
        return _errorDetail !== "Authentication failed"
            && _errorDetail !== "Quota exceeded"
            && _errorDetail !== "Configuration error";
    }

    /// Attempt auto-retry if the error is transient and retries remain.
    /// Returns true if an auto-retry was scheduled, false otherwise.
    /// When auto-retry is not possible, shows the suppressed error toast.
    function _tryAutoRetry(): bool {
        if (_autoRetryCount >= _maxAutoRetries || !_isTransientError() || _currentAudioFile === "") {
            Toaster.toast(qsTr("STT: %1").arg(_errorDetail), _errorHint, "error", Toast.Error);
            return false;
        }

        _autoRetryCount++;
        Logger.log("qml", "stt", "auto-retry | id=" + sessionId
            + " attempt=" + _autoRetryCount + "/" + _maxAutoRetries
            + " detail=" + _errorDetail);

        // Return to processing state immediately so the UI doesn't flash error
        _clearErrorState();
        _transcribedText = "";
        _state = "processing";
        autoRetryTimer.start();
        return true;
    }

    /// Spawn pw-record for the current segment and start level monitor.
    function _startRecording(): void {
        const segmentPath = _currentSegmentPath;
        const sampleRate = Config.stt?.recording?.sampleRate ?? 16000;
        const channels = Config.stt?.recording?.channels ?? 1;

        recordProcess.capturedSegmentPath = segmentPath;
        recordProcess.command = [
            "pw-record",
            "--format=s16",
            `--rate=${sampleRate}`,
            `--channels=${channels}`,
            segmentPath
        ];
        recordProcess.running = true;
        levelMonitorProcess.running = true;
    }

    /// Proceed to transcription after recording is complete.
    function _submitForTranscription(): void {
        Logger.log("qml", "stt", "transcribe | id=" + sessionId + " segments=" + _segmentFiles.length);
        if (_segmentFiles.length === 0) {
            console.error("[STT:D05] NO segments — aborting");
            _setErrorState("internal", "No audio segments", "Recording may have failed", false);
            return;
        }

        _state = "processing";

        if (_segmentFiles.length === 1) {
            _currentAudioFile = _segmentFiles[0];
            console.log("[STT:D06] single segment → transcribing:", _currentAudioFile);
            _startTranscription(_currentAudioFile);
        } else {
            console.log("[STT:D06] multi-segment → ffmpeg concat, count:", _segmentFiles.length);
            const outputPath = `${SttService._tempDir}/session_${sessionId}_combined.wav`;
            _currentAudioFile = outputPath;

            const n = _segmentFiles.length;
            const args = ["ffmpeg"];
            for (const f of _segmentFiles) {
                args.push("-i");
                args.push(f);
            }
            let filterInputs = "";
            for (let i = 0; i < n; i++) filterInputs += `[${i}:a]`;
            args.push("-filter_complex", `${filterInputs}concat=n=${n}:v=0:a=1[out]`,
                      "-map", "[out]", "-y", outputPath);

            concatProcess.command = args;
            concatProcess.running = true;
        }
    }

    /// Spawn the transcription helper script.
    function _startTranscription(audioFile: string): void {
        processingTimeoutTimer.restart();
        const model = Config.stt?.model ?? "gpt-4o-transcribe";
        Logger.log("qml", "stt", "api-call | id=" + sessionId + " file=" + audioFile);

        // Merge persistent config hints with per-session hints (deduplicated).
        // Use _snapshotVocabHints (captured at stop-time) rather than
        // SttService._sessionVocabHints, which is cleared before this async call fires.
        const persistentHints = Config.stt?.vocabularyHints ?? [];
        const sessionHints = job._snapshotVocabHints;
        const allHints = [...new Set([...persistentHints, ...sessionHints])];

        transcribeProcess.environment = ({
            STT_API_KEY: _resolvedApiKey,
            STT_VOCABULARY_HINTS: allHints.join(", ")
        });
        transcribeProcess.command = [
            _transcribeScript, audioFile, model
        ];
        transcribeProcess.running = true;
    }

    /// Start the clipboard → inject delivery chain.
    function _startDeliveryChain(): void {
        _state = "delivering";
        console.log("[STT:D11] → delivering, chaining wl-copy | id:", sessionId, "textLength:", _transcribedText.length);
        clipboardProcess.command = ["wl-copy", _transcribedText];
        clipboardProcess.running = true;
    }

    /// Delete temp files for this session.
    function _cleanupTempFiles(): void {
        if (sessionId !== "") {
            Quickshell.execDetached(["find", SttService._tempDir, "-maxdepth", "1",
                "-name", `session_${sessionId}_*`, "-delete"]);
        }
    }

    function _stopAllTimers(): void {
        elapsedTimer.stop();
        successTimer.stop();
        processingTimeoutTimer.stop();
        autoRetryTimer.stop();
        _removalTimer.stop();
    }

    /// Trigger animated removal — called by SttService orchestrator.
    /// Starts the per-job removal timer so the close animations driven by
    /// the `closing` flag (Wrapper.qml slide-up, Bar.qml embed clip)
    /// complete before the job is destroyed. Exposed as public to avoid
    /// SttService accessing _removalTimer across the component boundary.
    function startRemoval(): void {
        _removalTimer.start();
    }

    /// Cleanup for Component.onDestruction (called by service shutdown)
    function _destroyCleanup(): void {
        _stopAllTimers();
        if (sessionId !== "") _cleanupTempFiles();
        if (recordProcess.running) recordProcess.signal(9);
        if (levelMonitorProcess.running) levelMonitorProcess.running = false;
        if (transcribeProcess.running) transcribeProcess.signal(9);
        if (concatProcess.running) concatProcess.signal(9);
        if (clipboardProcess.running) clipboardProcess.running = false;
        if (injectProcess.running) injectProcess.running = false;
    }

    // ── State change handlers ──────────────────────────────���───────────

    on_StateChanged: {
        if (_state === "recording") {
            processingTimeoutTimer.stop();
            if (_recordingStartTime === 0) {
                _recordingStartTime = Date.now();
                _currentElapsed = _accumulatedSeconds;
            }
        } else if (_state === "processing") {
            // Defensive: should already be 0 via recordProcess.onExited,
            // but guard against any future code path that forgets.
            _recordingStartTime = 0;
        }

        if (_state === "success" || _state === "error") {
            _clearSttTargetIfOwned();
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

    // Toggle red border when user switches delivery choice in "ask" mode
    on_ActiveDeliveryChoiceChanged: {
        if (SttService._deliveryMode !== "ask" || _state === "idle") return;
        if (_activeDeliveryChoice === "clipboard") {
            AgentService.clearSttTarget();
        } else if (_targetWindowPid > 0 && _targetNvimActiveBuf >= 0) {
            AgentService.setSttTarget(_targetWindowPid, _targetNvimActiveBuf);
        }
    }

    // ── Timers ───────────────────────────────��─────────────────────────

    // Update _currentElapsed during recording
    readonly property Timer elapsedTimer: Timer {
        interval: 250
        repeat: true
        running: job.recording
        onTriggered: {
            if (job._recordingStartTime > 0)
                job._currentElapsed = job._accumulatedSeconds + (Date.now() - job._recordingStartTime) / 1000;
        }
    }

    // Auto-hide after success state
    readonly property Timer successTimer: Timer {
        interval: {
            const delay = Config.stt?.autoHideDelay ?? 1500;
            return Math.max(job._minAutoHideDelay, Math.min(job._maxAutoHideDelay, delay));
        }
        onTriggered: {
            if (job._state === "success") {
                Logger.log("qml", "stt", "auto-hide | id=" + job.sessionId);
                job.finished();
            }
        }
    }

    // Animated removal delay — per-job to avoid overwrite races
    readonly property Timer _removalTimer: Timer {
        // Must outlast close animations (Wrapper.qml hideAnim, Bar.qml embed clip = durations.normal)
        interval: Appearance.anim.durations.normal + 50
        onTriggered: SttService._finalizeRemoval(job)
    }

    // Detect stuck processing (API timeout or network hang)
    readonly property Timer processingTimeoutTimer: Timer {
        interval: Config.stt?.processingTimeout ?? 120000
        onTriggered: {
            Logger.log("qml", "stt", "timeout | id=" + job.sessionId);
            if (job.transcribeProcess.running) {
                job._pendingTimeoutKill = true;
                job.transcribeProcess.signal(9);
            }
            job._setErrorState("timeout", "Processing timed out", "Check your network connection", true);
            job._tryAutoRetry();
        }
    }

    // Delay before automatic retry (gives transient issues time to clear)
    readonly property Timer autoRetryTimer: Timer {
        interval: job._autoRetryDelayMs
        onTriggered: {
            Logger.log("qml", "stt", "auto-retry-fire | id=" + job.sessionId);
            job._startTranscription(job._currentAudioFile);
        }
    }

    // ── Processes ──────────────────────────────────────────────────────

    // pw-record: captures audio to WAV file
    readonly property Process recordProcess: Process {
        property string capturedSegmentPath: ""
        onExited: (code, status) => {
            const action = job._pendingRecordAction;
            job._pendingRecordAction = "";
            console.log("[STT:D08] recordProcess.onExited | id:", job.sessionId,
                "| code:", code, "| action:", action || "(none)",
                "| segPath:", capturedSegmentPath);

            if (action === "cancel") return;

            // Register completed segment file
            const segPath = capturedSegmentPath;
            if (segPath !== "") {
                const files = job._segmentFiles.slice();
                files.push(segPath);
                job._segmentFiles = files;
                console.log("[STT:D09] segment registered:", segPath, "| total:", files.length);
            } else {
                console.warn("[STT:D09] capturedSegmentPath is EMPTY");
            }

            if (action === "pause") {
                if (job._recordingStartTime > 0) {
                    job._accumulatedSeconds += (Date.now() - job._recordingStartTime) / 1000;
                    job._recordingStartTime = 0;
                }
                job._audioLevel = 0.0;
                job._state = "paused";
                console.log("[STT:D08] → paused, accumulated:", job._accumulatedSeconds.toFixed(1), "s");
            } else if (action === "submit") {
                if (job._recordingStartTime > 0) {
                    job._accumulatedSeconds += (Date.now() - job._recordingStartTime) / 1000;
                    job._currentElapsed = job._accumulatedSeconds;
                    job._recordingStartTime = 0;
                }
                job._audioLevel = 0.0;
                console.log("[STT:D08] → submit, elapsed:", job._accumulatedSeconds.toFixed(1), "s");
                job._submitForTranscription();
            } else if (code !== 0 && job._state === "recording") {
                console.error("[STT:D08] pw-record exited unexpectedly (code", code + ")");
                job._setErrorState("recording", "Recording failed", "Check audio device", false);
            }
        }
    }

    // Audio level monitor
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

    // ffmpeg: concatenate multi-segment recordings
    readonly property Process concatProcess: Process {
        onExited: (code, status) => {
            console.log("[STT:D20] concatProcess.onExited | id:", job.sessionId, "| code:", code);
            if (job._state !== "processing") return;

            if (code !== 0) {
                console.error("[STT:D20] ffmpeg concat FAILED (exit", code + ")");
                if (job._segmentFiles.length > 0) {
                    job._currentAudioFile = job._segmentFiles[job._segmentFiles.length - 1];
                    console.warn("[STT:D20] falling back to last segment:", job._currentAudioFile);
                    job._startTranscription(job._currentAudioFile);
                } else {
                    job._setErrorState("concat", "Failed to combine segments", "Is ffmpeg installed?", false);
                }
                return;
            }

            console.log("[STT:D20] concat OK → transcribing:", job._currentAudioFile);
            job._startTranscription(job._currentAudioFile);
        }
    }

    // Transcription via stt-transcribe.sh
    readonly property Process transcribeProcess: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const result = text.trim();
                if (result !== "")
                    job._transcribedText = result;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const errText = text.trim();
                if (errText !== "")
                    job._categorizeApiError(errText);
            }
        }
        onExited: (code, status) => {
            job.processingTimeoutTimer.stop();
            if (job._pendingTimeoutKill) {
                job._pendingTimeoutKill = false;
                console.log("[STT:D10] transcribeProcess.onExited — killed by timeout handler, ignoring");
                return;
            }
            if (job._state !== "processing") {
                console.log("[STT:D10] transcribeProcess.onExited — state is", job._state, ", ignoring");
                return;
            }
            Logger.log("qml", "stt", "transcribe-result | id=" + job.sessionId + " code=" + code + " textLen=" + job._transcribedText.length);
            if (code === 0 && job._transcribedText !== "") {
                // Mark as transcribed and signal readiness for FIFO delivery
                job._state = "transcribed";
                if (Config.stt?.cache?.deleteOnSuccess ?? true)
                    job._cleanupTempFiles();
                job.readyForDelivery();
            } else {
                Logger.log("qml", "stt", "transcribe-error | id=" + job.sessionId + " code=" + code + " detail=" + job._errorDetail + " raw=" + job._errorRaw);
                if (job._errorDetail === "") {
                    job._errorDetail = "Transcription failed";
                    job._errorHint = "Check logs for details";
                }
                job._setErrorState("api", job._errorDetail, job._errorHint, true);
                job._tryAutoRetry();
            }
        }
    }

    // Clipboard delivery via wl-copy
    readonly property Process clipboardProcess: Process {
        onExited: (code, status) => {
            Logger.log("qml", "stt", "clipboard-done | id=" + job.sessionId + " code=" + code);
            if (code !== 0) {
                console.error("[STT:D12] wl-copy FAILED (exit", code + ")");
                job._state = "success";
                SttService._onDeliveryComplete(job);
                return;
            }

            // Resolve effective delivery mode
            const effectiveMode = SttService._deliveryMode === "ask"
                ? job._activeDeliveryChoice
                : SttService._deliveryMode;
            Logger.log("qml", "stt", "delivery | id=" + job.sessionId + " mode=" + effectiveMode);

            if (effectiveMode !== "clipboard" && job._targetWindowAddress !== "") {
                if (job._targetWindowClass === "")
                    console.warn("[STT:D14] Window class unknown; inject will use Ctrl+V");
                const cmd = [job._injectScript, job._targetWindowAddress, job._targetWindowClass];
                if (effectiveMode === "submit") cmd.push("submit");
                Logger.log("qml", "stt", "inject-start | id=" + job.sessionId + " target=" + job._targetWindowAddress);
                injectProcess.environment = ({
                    STT_EXPECTED_TEXT: job._transcribedText,
                    STT_NVIM_SOCKET: job._targetNvimSocket,
                    STT_NVIM_ACTIVE_BUF: job._targetNvimActiveBuf.toString()
                });
                injectProcess.command = cmd;
                injectProcess.running = true;
            } else {
                console.log("[STT:D14] inject SKIPPED | id:", job.sessionId);
                job._injectionPath = "";
                job._injectionDowngraded = false;
                job._injectionSubmitted = false;
                job._state = "success";
                SttService._onDeliveryComplete(job);
            }
        }
    }

    // Window injection via stt-inject.sh
    readonly property Process injectProcess: Process {
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (!line.startsWith("{")) return;
                try {
                    const result = JSON.parse(line);
                    job._injectionPath = result.path ?? "";
                    job._injectionDowngraded = result.downgraded ?? false;
                    job._injectionSubmitted = result.submitted ?? false;

                    if (result.downgraded) {
                        Toaster.toast(
                            qsTr("STT: Submit downgraded"),
                            qsTr("Agent RPC unavailable — text pasted but not submitted"),
                            "",
                            Toast.Warning
                        );
                    } else if (result.path === "rpc" && !result.submitted) {
                        const userRequestedSubmit = SttService._deliveryMode === "submit" ||
                            (SttService._deliveryMode === "ask" && job._activeDeliveryChoice === "submit");
                        if (userRequestedSubmit) {
                            Toaster.toast(
                                qsTr("STT: Submit unconfirmed"),
                                qsTr("Text injected but Enter delivery could not be confirmed"),
                                "",
                                Toast.Warning
                            );
                        }
                    }
                    Logger.log("qml", "stt", "inject-result | id=" + job.sessionId + " " + JSON.stringify(result));
                } catch (e) {
                    console.warn("[STT:D16] failed to parse inject stdout:", line);
                }
            }
        }
        stderr: SplitParser {
            onRead: data => {
                console.log("[STT:D16:stderr]", data.trim());
            }
        }
        onExited: (code, status) => {
            console.log("[STT:D16] injectProcess.onExited | id:", job.sessionId,
                "| code:", code, "| path:", job._injectionPath);
            if (code !== 0)
                console.warn("[STT:D16] inject script FAILED (code", code + ") — non-fatal, clipboard still has text");
            job._state = "success";
            SttService._onDeliveryComplete(job);
        }
    }
}
