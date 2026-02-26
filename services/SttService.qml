pragma Singleton

import qs.config
import qs.services
import qs.utils
import Quickshell
import Quickshell.Io
import Symmetria
import QtQuick

/// Native speech-to-text service using pw-record + OpenAI API.
///
/// Replaces HyprWhsprService with direct process management instead of
/// file-watching / FIFO / inotifywait / systemd orchestration.
///
/// Pipeline: pw-record → WAV file → curl (OpenAI API) → wl-copy [→ sendshortcut inject]
///
/// State machine:
///   idle → recording ⇄ paused → processing → success/error → idle
///
/// Audio level comes from a separate pw-record → od → awk pipeline at ~10Hz.
/// PipeWire natively multiplexes multiple readers from the same audio source.
Singleton {
    id: root

    // ─────────────────────────────────────────────────────────────────────────
    // Public interface (matches HyprWhsprService for UI compatibility)
    // ─────────────────────────────────────────────────────────────────────────

    /// Current state: "idle", "recording", "paused", "processing", "error", "success"
    readonly property string state: _state

    /// Audio level (0.0-1.0) during recording
    readonly property real audioLevel: _audioLevel

    /// Whether any non-idle state is active (controls drawer visibility).
    /// _keepDrawerOpen can diverge from _state in the API-key-missing path:
    /// start() sets _keepDrawerOpen=true, then _setErrorState moves to "error".
    /// Without _keepDrawerOpen, the brief idle→error transition would flicker the drawer.
    readonly property bool active: _state !== "idle" && _keepDrawerOpen

    /// Whether currently recording
    readonly property bool recording: _state === "recording"

    /// Current speech-to-text language code (e.g., "en", "es")
    readonly property string language: _currentLanguage

    /// Elapsed recording time in seconds (pause-aware)
    readonly property real elapsedSeconds: _currentElapsed

    /// Error detail properties for the drawer UI
    readonly property string errorDetail: _errorDetail
    readonly property string errorHint: _errorHint
    readonly property string errorRaw: _errorRaw
    readonly property string errorSource: _errorSource

    /// Transcribed text result (for success state preview)
    readonly property string transcribedText: _transcribedText

    /// Emitted when an action is successfully dispatched (not a no-op).
    /// Used by Content.qml to animate the corresponding control button.
    signal actionTriggered(string action)

    /// Whether the delivery mode radio toggle should be shown
    readonly property bool isAskMode: _deliveryMode === "ask"

    /// The user's runtime delivery choice for "ask" mode
    readonly property string activeDeliveryChoice: _activeDeliveryChoice

    /// Injection delivery path: "rpc" (Neovim), "paste" (sendshortcut), "" (clipboard-only/none)
    readonly property string injectionPath: _injectionPath

    /// Whether submit was downgraded to inject (RPC unavailable on sendshortcut path)
    readonly property bool injectionDowngraded: _injectionDowngraded

    /// Whether the RPC path confirmed that Enter (submit) was actually sent
    readonly property bool injectionSubmitted: _injectionSubmitted

    // ─────────────────────────────────────────────────────────────────────────
    // Internal state
    // ─────────────────────────────────────────────────────────────────────────

    property string _state: "idle"
    property real _audioLevel: 0.0
    property bool _keepDrawerOpen: false
    property string _currentLanguage: ""
    property string _pendingRestartLang: ""
    property string _transcribedText: ""

    // Error detail properties
    property string _errorDetail: ""
    property string _errorHint: ""
    property string _errorSource: ""  // "api", "config", "recording", "concat", "timeout", "internal"
    property string _errorRaw: ""

    // Elapsed time tracking
    property real _currentElapsed: 0
    property real _recordingStartTime: 0
    property real _accumulatedSeconds: 0
    readonly property int _elapsedTimerInterval: 250

    // Auto-hide delay constraints (ms)
    readonly property int _minAutoHideDelay: 500
    readonly property int _maxAutoHideDelay: 10000

    // Toggle debouncing
    property real _lastToggleTime: 0
    readonly property int _toggleDebounceMs: 200

    // Segment management
    property int _segmentCounter: 0
    property string _sessionId: ""
    property var _segmentFiles: []
    property string _currentAudioFile: ""  // Combined file for transcription/retry

    // Target window for inject delivery (captured at submit time)
    property string _targetWindowAddress: ""
    property string _targetWindowClass: ""
    property int _targetWindowPid: -1
    // Target Neovim socket (resolved from AgentService at start-time)
    property string _targetNvimSocket: ""
    property int _targetNvimActiveBuf: -1

    // Pending action for recordProcess.onExited callback
    // Values: "" (none), "pause", "submit", "cancel"
    property string _pendingRecordAction: ""

    // Runtime delivery choice for "ask" mode.
    // Persists across recordings within the same shell session.
    // First-time default is "clipboard" (safest).
    property string _activeDeliveryChoice: "clipboard"

    // Injection result feedback (populated by injectProcess stdout parsing)
    property string _injectionPath: ""         // "rpc" | "paste" | "" (clipboard-only/none)
    property bool _injectionDowngraded: false  // true if submit was downgraded to inject
    property bool _injectionSubmitted: false   // true if RPC confirmed Enter was sent

    // Directories
    readonly property string _runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string _tempDir: `${_runtimeDir}/symmetria-stt`

    // Script paths (resolved relative to project root)
    readonly property string _levelMonitorScript: Qt.resolvedUrl("../scripts/stt-level-monitor.sh").toString().replace("file://", "")
    readonly property string _transcribeScript: Qt.resolvedUrl("../scripts/stt-transcribe.sh").toString().replace("file://", "")
    readonly property string _injectScript: Qt.resolvedUrl("../scripts/stt-inject.sh").toString().replace("file://", "")

    // Delivery mode: "clipboard" (default), "inject", "submit", or "ask" (runtime radio toggle)
    readonly property string _deliveryMode: {
        const mode = Config.stt?.deliveryMode ?? "clipboard";
        if (mode === "inject" || mode === "submit" || mode === "ask") return mode;
        return "clipboard";
    }

    // API key: config value takes priority, then environment variable
    readonly property string _resolvedApiKey: {
        const configKey = Config.stt?.apiKey ?? "";
        if (configKey !== "") return configKey;
        return Quickshell.env("OPENAI_API_KEY") || "";
    }

    // Current segment file path (computed from session + counter)
    // Note: _segmentCounter is incremented in resume() before _startRecording()
    // is called, so this path is always correct at _startRecording() time.
    // The actual path used for recording is snapshotted via recordProcess.capturedSegmentPath.
    readonly property string _currentSegmentPath: {
        if (_sessionId === "") return "";
        return `${_tempDir}/session_${_sessionId}_segment_${_segmentCounter}.wav`;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Orchestrator commands
    // ─────────────────────────────────────────────────────────────────────────

    /// Toggle: start if idle, submit if active, retry if error.
    function toggle(lang: string): void {
        const now = Date.now();
        if (now - _lastToggleTime < _toggleDebounceMs) {
            console.log("[STT:D19] toggle() DEBOUNCED | elapsed:", now - _lastToggleTime, "ms");
            return;
        }
        console.log("[STT:D19] toggle() | state:", _state,
            "| keepDrawerOpen:", _keepDrawerOpen, "| lang:", lang);

        if (_state === "idle" || !_keepDrawerOpen) {
            _lastToggleTime = now;
            start(lang);
        } else if (_state === "recording" || _state === "paused") {
            _lastToggleTime = now;
            stop();
        } else if (_state === "error") {
            _lastToggleTime = now;
            retry();
        }
        // Processing/success: no-op — don't update debounce timestamp
    }

    /// Start recording with optional language code.
    function start(lang: string): void {
        if (_state === "recording" || _state === "paused" || _state === "processing") {
            console.warn("[STT] start() called while already active — ignoring");
            return;
        }
        console.log("[STT:D18] start() called | lang:", lang,
            "| currentState:", _state,
            "| deliveryMode:", _deliveryMode);
        // Check API key before starting
        if (_resolvedApiKey === "") {
            _keepDrawerOpen = true;
            _setErrorState("config", "API key not configured",
                "Set OPENAI_API_KEY env var or stt.apiKey in shell.json");
            return;
        }

        const safeLang = _sanitizeLanguage(lang);

        // Clear stale terminal states
        if (_state === "error" || _state === "success") {
            _clearErrorState();
            _transcribedText = "";
        }

        _keepDrawerOpen = true;
        if (safeLang) _currentLanguage = safeLang;

        // Initialize session
        _sessionId = Date.now().toString();
        _segmentCounter = 0;
        _segmentFiles = [];
        _currentAudioFile = "";
        _recordingStartTime = Date.now();
        _accumulatedSeconds = 0;
        _currentElapsed = 0;
        _pendingRecordAction = "";
        _injectionPath = "";
        _injectionDowngraded = false;
        _injectionSubmitted = false;

        // Transition to recording before capture so that:
        // 1. active (= _state !== "idle" && _keepDrawerOpen) becomes true → drawer opens
        // 2. tempDirProcess.onExited guard (root._state === "idle") passes for normal flow
        //    but still catches cancel (which synchronously resets _state to "idle")
        // 3. setSttTarget() in _resolveAgentTarget() fires after state is "recording",
        //    so the red border and drawer appear simultaneously
        _state = "recording";

        // Capture target window and resolve agent data synchronously.
        // The user just pressed the STT keybind from their focused terminal.
        // AgentService provides instant Neovim socket lookup (no async shell script).
        _captureTargetWindow();
        _resolveAgentTarget();
        console.log("[STT:D18] session initialized | id:", _sessionId,
            "| target:", _targetWindowAddress, "class:", _targetWindowClass,
            "| nvimSocket:", _targetNvimSocket);

        // Ensure temp dir exists, then start recording
        tempDirProcess.running = true;
    }

    /// Stop recording and submit for transcription.
    function stop(): void {
        if (_state !== "recording" && _state !== "paused") return;
        console.log("[STT:D01] stop() called | state:", _state,
            "| deliveryMode:", _deliveryMode,
            "| askChoice:", _activeDeliveryChoice,
            "| sessionId:", _sessionId,
            "| segments:", _segmentFiles.length);
        actionTriggered("stop");
        // Target was fixed at start() — no re-capture needed.
        // The user may have switched windows during recording, but injection
        // goes to the terminal that was active when recording started.
        console.log("[STT:D02] stop() | target:", _targetWindowAddress,
            "| class:", _targetWindowClass,
            "| nvimSocket:", _targetNvimSocket);

        if (_state === "paused") {
            console.log("[STT:D03] paused path → direct _submitForTranscription()");
            _submitForTranscription();
            return;
        }

        // Stop recording first, then submit on exit
        console.log("[STT:D03] recording path → SIGTERM pw-record, pending submit");
        _pendingRecordAction = "submit";
        levelMonitorProcess.running = false;
        recordProcess.running = false;  // SIGTERM → pw-record finalizes WAV
    }

    /// Toggle pause: pause if recording, resume if paused.
    function pause(): void {
        if (_state === "recording") {
            actionTriggered("pause");
            _pendingRecordAction = "pause";
            levelMonitorProcess.running = false;
            recordProcess.running = false;  // SIGTERM → finalize current segment
        } else if (_state === "paused") {
            actionTriggered("resume");
            resume();
        }
    }

    /// Resume from pause. Starts a new segment.
    function resume(): void {
        if (_state !== "paused") return;
        _segmentCounter++;
        _startRecording();
        _recordingStartTime = Date.now();
        _state = "recording";
    }

    /// Cancel recording: kill processes, discard audio, close drawer.
    function cancel(): void {
        actionTriggered("cancel");
        _cancelInternal();
    }

    /// Restart: cancel + re-start recording with same language.
    function restart(): void {
        actionTriggered("restart");
        const savedLang = _currentLanguage || _pendingRestartLang || "";
        restartDelayTimer.stop();
        _cancelInternal();
        _pendingRestartLang = savedLang;
        restartDelayTimer.start();
    }

    /// Retry failed transcription with the same audio file.
    function retry(): void {
        if (_state !== "error") return;
        actionTriggered("retry");
        console.log("[STT:D21] retry() | audioFile:", _currentAudioFile,
            "| targetAddr:", _targetWindowAddress, "| targetClass:", _targetWindowClass);

        if (_currentAudioFile === "") {
            _setErrorState("internal", "No audio file to retry", "Start a new recording");
            return;
        }

        _clearErrorState();
        _transcribedText = "";
        _state = "processing";
        _startTranscription(_currentAudioFile);
    }

    /// Switch the runtime delivery choice (only effective in "ask" mode).
    function setDeliveryChoice(mode: string): void {
        if (_deliveryMode !== "ask") {
            console.debug("[STT] setDeliveryChoice() ignored: deliveryMode is", _deliveryMode, "(not ask)");
            return;
        }
        if (mode !== "clipboard" && mode !== "inject" && mode !== "submit") return;
        if (_activeDeliveryChoice === mode) return;
        _activeDeliveryChoice = mode;
        actionTriggered("mode-" + mode);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _sanitizeLanguage(lang: string): string {
        if (!lang) return "";
        const sanitized = lang.replace(/[^a-zA-Z-]/g, "");
        if (sanitized.length < 2 || sanitized.length > 5) {
            console.warn("[STT] Invalid language code:", lang);
            return "";
        }
        return sanitized;
    }

    function _setErrorState(source: string, detail: string, hint: string): void {
        _errorSource = source;
        _errorDetail = detail;
        _errorHint = hint;
        _state = "error";
        // Clean up temp segment files on error. The combined/single audio file
        // (_currentAudioFile) is preserved for retry; only raw segments are cleaned.
        if (_sessionId !== "" && _segmentFiles.length > 0 && _currentAudioFile !== "") {
            // Delete individual segments but keep the combined file for retry
            for (const seg of _segmentFiles) {
                if (seg !== _currentAudioFile) {
                    Quickshell.execDetached(["rm", "-f", seg]);
                }
            }
        }
    }

    function _clearErrorState(): void {
        _errorSource = "";
        _errorDetail = "";
        _errorHint = "";
        _errorRaw = "";
    }

    /// Capture the currently active window for inject delivery.
    /// Called at both start() and stop() — start() captures an eager fallback,
    /// stop() overwrites with a fresher value if a toplevel is available.
    /// In ask mode, we capture regardless of _activeDeliveryChoice because
    /// the user may switch to inject/submit before delivery completes.
    function _captureTargetWindow(): void {
        if (_deliveryMode === "clipboard") {
            console.log("[STT:D04] _captureTargetWindow() skipped — deliveryMode is clipboard");
            return;
        }
        const toplevel = Hypr.activeToplevel;
        if (toplevel) {
            const prevAddr = _targetWindowAddress;
            // .address lacks "0x" prefix; sendshortcut needs it
            _targetWindowAddress = `0x${toplevel.address}`;
            _targetWindowClass = toplevel.lastIpcObject?.class ?? "";
            _targetWindowPid = toplevel.lastIpcObject?.pid ?? -1;
            console.log("[STT:D04] _captureTargetWindow() captured | address:", _targetWindowAddress,
                "| class:", _targetWindowClass, "| pid:", _targetWindowPid,
                "| prevAddress:", prevAddr,
                "| changed:", prevAddr !== _targetWindowAddress);
        } else {
            console.warn("[STT:D04] _captureTargetWindow() — NO activeToplevel! Keeping fallback:",
                _targetWindowAddress, "class:", _targetWindowClass);
        }
        // If no toplevel, preserve any previously captured value (start-time fallback)
    }

    /// Resolve agent data from AgentService using captured terminal PID.
    /// Sets _targetNvimSocket and _targetNvimActiveBuf deterministically.
    /// Notifies AgentService for project pill red border.
    function _resolveAgentTarget(): void {
        _targetNvimSocket = "";
        _targetNvimActiveBuf = -1;

        if (!AgentService.bridgeRunning) {
            return;  // No agent data available — sendshortcut fallback
        }

        const agent = AgentService.agentForTerminal(_targetWindowPid);
        if (!agent) {
            return;  // Non-agent window — no highlight, sendshortcut fallback
        }

        _targetNvimSocket = AgentService.nvimSocketForAgent(agent);
        _targetNvimActiveBuf = agent.buf ?? -1;

        // Set highlight based on effective delivery mode
        const effectiveMode = _deliveryMode === "ask" ? _activeDeliveryChoice : _deliveryMode;
        if (effectiveMode !== "clipboard") {
            AgentService.setSttTarget(_targetWindowPid, agent.buf ?? -1);
        }
    }

    /// Categorize API errors from stt-transcribe.sh stderr output.
    /// Format: ERROR:<http_code>:<message>
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

    function _cancelInternal(): void {
        // Set before SIGKILL so recordProcess.onExited (fires async) sees "cancel"
        // and returns early. Cleared at the end of this function after sync work.
        _pendingRecordAction = "cancel";
        _stopAllTimers();

        // Kill active processes (signal(9) = SIGKILL; Process.kill() is not exposed to QML)
        if (recordProcess.running) recordProcess.signal(9);
        if (levelMonitorProcess.running) levelMonitorProcess.running = false;
        if (transcribeProcess.running) transcribeProcess.signal(9);
        if (concatProcess.running) concatProcess.signal(9);
        if (tempDirProcess.running) tempDirProcess.running = false;

        // clipboardProcess and injectProcess are intentionally not interrupted —
        // if delivery is already in flight, completing silently is acceptable
        // (clipboard always has the text as fallback).

        // Clean up temp files
        _cleanupTempFiles();

        // Reset all state
        _keepDrawerOpen = false;
        _state = "idle";
        _currentLanguage = "";
        _pendingRestartLang = "";
        _recordingStartTime = 0;
        _accumulatedSeconds = 0;
        _currentElapsed = 0;
        _audioLevel = 0.0;
        _transcribedText = "";
        _segmentFiles = [];
        _currentAudioFile = "";
        _targetWindowAddress = "";
        _targetWindowClass = "";
        _targetWindowPid = -1;
        _targetNvimSocket = "";
        _targetNvimActiveBuf = -1;
        _injectionPath = "";
        _injectionDowngraded = false;
        _injectionSubmitted = false;
        AgentService.clearSttTarget();
        _sessionId = "";
        _pendingRecordAction = "";
        _clearErrorState();
    }

    function _stopAllTimers(): void {
        successTimer.stop();
        restartDelayTimer.stop();
        processingTimeoutTimer.stop();
    }

    /// Spawn pw-record for the current segment and start level monitor.
    function _startRecording(): void {
        const segmentPath = _currentSegmentPath;
        const sampleRate = Config.stt?.recording?.sampleRate ?? 16000;
        const channels = Config.stt?.recording?.channels ?? 1;

        // Capture segment path on the process so onExited reads the correct
        // path even if _segmentCounter is incremented before the exit fires.
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
        console.log("[STT:D05] _submitForTranscription() | segments:", _segmentFiles.length,
            "| files:", JSON.stringify(_segmentFiles));
        if (_segmentFiles.length === 0) {
            console.error("[STT:D05] NO segments — aborting");
            _setErrorState("internal", "No audio segments", "Recording may have failed");
            return;
        }

        _state = "processing";

        if (_segmentFiles.length === 1) {
            // Single segment — use directly
            _currentAudioFile = _segmentFiles[0];
            console.log("[STT:D06] single segment → transcribing:", _currentAudioFile);
            _startTranscription(_currentAudioFile);
        } else {
            // Multiple segments — concatenate with ffmpeg
            console.log("[STT:D06] multi-segment → ffmpeg concat, count:", _segmentFiles.length);
            const outputPath = `${_tempDir}/session_${_sessionId}_combined.wav`;
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
        processingTimeoutTimer.start();
        const model = Config.stt?.model ?? "gpt-4o-transcribe";
        const lang = _currentLanguage || "en";
        console.log("[STT:D07] _startTranscription() | file:", audioFile,
            "| model:", model, "| lang:", lang,
            "| timeoutMs:", processingTimeoutTimer.interval);

        // Pass API key via environment to avoid exposure in /proc/<pid>/cmdline
        transcribeProcess.environment = ({ STT_API_KEY: _resolvedApiKey });
        transcribeProcess.command = [
            _transcribeScript, audioFile, lang, model
        ];
        transcribeProcess.running = true;
    }

    /// Delete temp files for the current session.
    function _cleanupTempFiles(): void {
        if (_sessionId !== "") {
            Quickshell.execDetached(["find", _tempDir, "-maxdepth", "1",
                "-name", `session_${_sessionId}_*`, "-delete"]);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Timers
    // ─────────────────────────────────────────────────────────────────────────

    // Update _currentElapsed during recording
    Timer {
        id: elapsedTimer
        interval: root._elapsedTimerInterval
        repeat: true
        running: root.recording
        onTriggered: {
            if (root._recordingStartTime > 0)
                root._currentElapsed = root._accumulatedSeconds + (Date.now() - root._recordingStartTime) / 1000;
        }
    }

    // Auto-hide after success state
    Timer {
        id: successTimer
        interval: {
            const delay = Config.stt?.autoHideDelay ?? 1500;
            return Math.max(root._minAutoHideDelay, Math.min(root._maxAutoHideDelay, delay));
        }
        onTriggered: {
            console.log("[STT:D17] successTimer fired | state:", root._state,
                "| delay was:", interval, "ms");
            if (root._state === "success") {
                console.log("[STT:D17] → auto-hiding (idle)");
                root._keepDrawerOpen = false;
                root._state = "idle";
            }
        }
    }

    // Detect stuck processing (API timeout or network hang)
    Timer {
        id: processingTimeoutTimer
        interval: Config.stt?.processingTimeout ?? 120000
        onTriggered: {
            console.error("[STT] Processing timed out");
            if (transcribeProcess.running) transcribeProcess.signal(9);
            root._setErrorState("timeout", "Processing timed out", "Check your network connection");
        }
    }

    // Delayed start after cancel (used by restart)
    Timer {
        id: restartDelayTimer
        interval: 500
        onTriggered: {
            if (root._pendingRestartLang !== "") {
                const lang = root._pendingRestartLang;
                root._pendingRestartLang = "";
                root.start(lang);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Processes
    // ─────────────────────────────────────────────────────────────────────────

    // Ensure temp directory exists before recording
    Process {
        id: tempDirProcess
        command: ["mkdir", "-p", root._tempDir]
        onExited: (code, status) => {
            // Guard: if cancel fired while mkdir was running, don't start recording
            if (root._state === "idle") return;
            if (code !== 0) {
                console.error("[STT] Failed to create temp directory:", root._tempDir);
                root._setErrorState("internal", "Failed to create temp directory", "Check permissions");
                return;
            }
            root._startRecording();
        }
    }

    // pw-record: captures audio to WAV file (command set dynamically)
    Process {
        id: recordProcess
        // Captured at _startRecording() time so onExited reads the path that was
        // active when this invocation began, not the post-resume counter value.
        property string capturedSegmentPath: ""
        onExited: (code, status) => {
            const action = root._pendingRecordAction;
            root._pendingRecordAction = "";
            console.log("[STT:D08] recordProcess.onExited | code:", code,
                "| action:", action || "(none)",
                "| segPath:", capturedSegmentPath,
                "| state:", root._state);

            // Cancel already handled everything
            if (action === "cancel") {
                console.log("[STT:D08] action=cancel → returning early");
                return;
            }

            // Register completed segment file
            const segPath = capturedSegmentPath;
            if (segPath !== "") {
                const files = root._segmentFiles.slice();
                files.push(segPath);
                root._segmentFiles = files;
                console.log("[STT:D09] segment registered:", segPath, "| total segments:", files.length);
            } else {
                console.warn("[STT:D09] capturedSegmentPath is EMPTY — no segment registered");
            }

            if (action === "pause") {
                // Accumulate elapsed time from this segment
                if (root._recordingStartTime > 0) {
                    root._accumulatedSeconds += (Date.now() - root._recordingStartTime) / 1000;
                    root._recordingStartTime = 0;
                }
                root._audioLevel = 0.0;
                root._state = "paused";
                console.log("[STT:D08] → paused, accumulated:", root._accumulatedSeconds.toFixed(1), "s");
            } else if (action === "submit") {
                // Accumulate final elapsed time
                if (root._recordingStartTime > 0) {
                    root._accumulatedSeconds += (Date.now() - root._recordingStartTime) / 1000;
                    root._currentElapsed = root._accumulatedSeconds;
                    root._recordingStartTime = 0;
                }
                root._audioLevel = 0.0;
                console.log("[STT:D08] → submit path, elapsed:", root._accumulatedSeconds.toFixed(1), "s, calling _submitForTranscription()");
                root._submitForTranscription();
            } else if (code !== 0 && root._state === "recording") {
                // Unexpected exit during recording
                console.error("[STT:D08] pw-record exited unexpectedly (code", code + ")");
                root._setErrorState("recording", "Recording failed", "Check audio device");
            } else {
                console.log("[STT:D08] no matching action, code:", code, "state:", root._state, "— no-op");
            }
        }
    }

    // Audio level monitor (separate pw-record → od → awk pipeline, ~10Hz output)
    Process {
        id: levelMonitorProcess
        command: [root._levelMonitorScript]
        stdout: SplitParser {
            onRead: data => {
                const level = parseFloat(data.trim());
                if (!isNaN(level) && isFinite(level))
                    root._audioLevel = Math.min(1.0, Math.max(0.0, level));
            }
        }
    }

    // ffmpeg: concatenate multi-segment recordings (command set dynamically)
    Process {
        id: concatProcess
        onExited: (code, status) => {
            console.log("[STT:D20] concatProcess.onExited | code:", code, "| state:", root._state);
            // Ignore exit if cancel already reset state
            if (root._state !== "processing") {
                console.log("[STT:D20] state is not processing — ignoring");
                return;
            }

            if (code !== 0) {
                console.error("[STT:D20] ffmpeg concat FAILED (exit", code + ")");
                // Fallback: use last segment only
                if (root._segmentFiles.length > 0) {
                    root._currentAudioFile = root._segmentFiles[root._segmentFiles.length - 1];
                    console.warn("[STT:D20] falling back to last segment:", root._currentAudioFile);
                    root._startTranscription(root._currentAudioFile);
                } else {
                    root._setErrorState("concat", "Failed to combine segments", "Is ffmpeg installed?");
                }
                return;
            }
            console.log("[STT:D20] concat OK → transcribing combined file:", root._currentAudioFile);
            root._startTranscription(root._currentAudioFile);
        }
    }

    // Transcription via stt-transcribe.sh (command set dynamically)
    Process {
        id: transcribeProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const result = text.trim();
                if (result !== "")
                    root._transcribedText = result;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const errText = text.trim();
                if (errText !== "")
                    root._categorizeApiError(errText);
            }
        }
        onExited: (code, status) => {
            processingTimeoutTimer.stop();
            // Guard: if cancel already reset state, don't overwrite with error
            if (root._state !== "processing") {
                console.log("[STT:D10] transcribeProcess.onExited — state is not processing (" + root._state + "), ignoring");
                return;
            }
            console.log("[STT:D10] transcribeProcess.onExited | code:", code,
                "| textLength:", root._transcribedText.length,
                "| textPreview:", root._transcribedText.substring(0, 80),
                "| errorDetail:", root._errorDetail);
            if (code === 0 && root._transcribedText !== "") {
                root._state = "success";
                console.log("[STT:D11] → success, chaining wl-copy | textLength:", root._transcribedText.length);
                // Copy to clipboard
                clipboardProcess.capturedSessionId = root._sessionId;
                clipboardProcess.command = ["wl-copy", root._transcribedText];
                clipboardProcess.running = true;
                // Clean up temp files on success
                if (Config.stt?.cache?.deleteOnSuccess ?? true)
                    root._cleanupTempFiles();
            } else {
                console.error("[STT:D10] → error path | code:", code,
                    "| hasText:", root._transcribedText !== "",
                    "| errorDetail:", root._errorDetail,
                    "| errorRaw:", root._errorRaw);
                // Error — categorization already happened in stderr collector
                if (root._errorDetail === "")
                    root._setErrorState("api", "Transcription failed", "Check logs for details");
                else {
                    root._errorSource = "api";
                    root._state = "error";
                }
            }
        }
    }

    // Clipboard delivery via wl-copy
    Process {
        id: clipboardProcess
        property string capturedSessionId: ""
        onExited: (code, status) => {
            console.log("[STT:D12] clipboardProcess.onExited | code:", code,
                "| deliveryMode:", root._deliveryMode,
                "| askChoice:", root._activeDeliveryChoice,
                "| targetAddr:", root._targetWindowAddress,
                "| targetClass:", root._targetWindowClass);
            if (code !== 0) {
                console.error("[STT:D12] wl-copy FAILED (exit", code + ") — clearing target, aborting inject chain");
                root._targetWindowAddress = "";
                root._targetWindowClass = "";
                return;
            }
            if (clipboardProcess.capturedSessionId !== root._sessionId) {
                console.warn("[STT:D12] session changed — discarding stale injection");
                return;
            }
            // Resolve effective delivery mode ("ask" → runtime choice)
            const effectiveMode = root._deliveryMode === "ask"
                ? root._activeDeliveryChoice
                : root._deliveryMode;
            console.log("[STT:D13] effectiveMode resolved:", effectiveMode,
                "| from:", root._deliveryMode === "ask" ? "ask→" + root._activeDeliveryChoice : root._deliveryMode);

            // Refresh socket/buffer from AgentService — may have changed during recording
            if (root._targetWindowPid > 0 && AgentService.bridgeRunning) {
                const freshAgent = AgentService.agentForTerminal(root._targetWindowPid);
                if (freshAgent) {
                    const freshSocket = AgentService.nvimSocketForAgent(freshAgent);
                    const freshBuf = freshAgent.buf ?? -1;
                    if (freshSocket !== root._targetNvimSocket || freshBuf !== root._targetNvimActiveBuf) {
                        console.log("[STT:D13] socket refreshed | old:", root._targetNvimSocket,
                            "→ new:", freshSocket, "| oldBuf:", root._targetNvimActiveBuf, "→ newBuf:", freshBuf);
                        root._targetNvimSocket = freshSocket;
                        root._targetNvimActiveBuf = freshBuf;
                    }
                }
            }

            // Chain window injection after successful clipboard write
            if (effectiveMode !== "clipboard" && root._targetWindowAddress !== "") {
                if (root._targetWindowClass === "")
                    console.warn("[STT:D14] Window class unknown; inject will use Ctrl+V");
                const cmd = [root._injectScript, root._targetWindowAddress, root._targetWindowClass];
                if (effectiveMode === "submit") cmd.push("submit");
                console.log("[STT:D15] → launching inject | cmd:", JSON.stringify(cmd));
                // Pass expected text, pre-determined Neovim socket + buffer (captured at stop-time)
                injectProcess.capturedSessionId = root._sessionId;
                injectProcess.environment = ({
                    STT_EXPECTED_TEXT: root._transcribedText,
                    STT_NVIM_SOCKET: root._targetNvimSocket,
                    STT_NVIM_ACTIVE_BUF: root._targetNvimActiveBuf.toString()
                });
                injectProcess.command = cmd;
                injectProcess.running = true;
            } else {
                console.log("[STT:D14] inject SKIPPED | reason:",
                    effectiveMode === "clipboard" ? "effectiveMode=clipboard" :
                    root._targetWindowAddress === "" ? "no targetWindowAddress" : "unknown");
                root._injectionPath = "";  // No injection attempted
                root._injectionDowngraded = false;
                root._injectionSubmitted = false;
            }
        }
    }

    // Window injection via stt-inject.sh (best-effort, non-fatal)
    // Parses structured JSON from stdout: {"path":"rpc"|"paste"|"none","success":bool,"downgraded":bool,"submitted":bool}
    Process {
        id: injectProcess
        property string capturedSessionId: ""
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (!line.startsWith("{")) return;
                try {
                    const result = JSON.parse(line);
                    if (injectProcess.capturedSessionId !== root._sessionId) {
                        console.warn("[STT:D16] session changed — discarding stale inject result");
                        return;
                    }
                    root._injectionPath = result.path ?? "";
                    root._injectionDowngraded = result.downgraded ?? false;
                    root._injectionSubmitted = result.submitted ?? false;

                    if (result.downgraded) {
                        Toaster.toast(
                            qsTr("STT: Submit downgraded"),
                            qsTr("Agent RPC unavailable — text pasted but not submitted"),
                            "",
                            Toast.Warning
                        );
                    } else if (result.path === "rpc" && !result.submitted) {
                        // Check if user actually requested submit
                        const userRequestedSubmit = root._deliveryMode === "submit" ||
                            (root._deliveryMode === "ask" && root._activeDeliveryChoice === "submit");
                        if (userRequestedSubmit) {
                            Toaster.toast(
                                qsTr("STT: Submit unconfirmed"),
                                qsTr("Text injected but Enter delivery could not be confirmed"),
                                "",
                                Toast.Warning
                            );
                        }
                    }
                    console.log("[STT:D16] inject result parsed:", JSON.stringify(result));
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
            console.log("[STT:D16] injectProcess.onExited | code:", code,
                "| path:", root._injectionPath,
                "| downgraded:", root._injectionDowngraded);
            if (code !== 0)
                console.warn("[STT:D16] inject script FAILED (code", code + ") — non-fatal, clipboard still has text");
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // State change handlers
    // ─────────────────────────────────────────────────────────────────────────

    onStateChanged: {
        if (_state === "recording") {
            processingTimeoutTimer.stop();
            if (_recordingStartTime === 0) {
                _recordingStartTime = Date.now();
                _currentElapsed = _accumulatedSeconds;
            }
        } else if (_state === "processing") {
            _recordingStartTime = 0;
        }

        if (_state === "success") {
            successTimer.start();
        } else {
            successTimer.stop();
        }

        if (_state === "idle") {
            _recordingStartTime = 0;
            _accumulatedSeconds = 0;
            _currentElapsed = 0;
            _currentLanguage = "";
            _injectionPath = "";
            _injectionDowngraded = false;
            _injectionSubmitted = false;
            AgentService.clearSttTarget();
        }
    }

    onRecordingChanged: {
        if (!recording)
            _audioLevel = 0.0;
    }

    // Toggle red border when user switches delivery choice in "ask" mode
    on_ActiveDeliveryChoiceChanged: {
        if (_deliveryMode !== "ask" || _state === "idle") return;
        if (_activeDeliveryChoice === "clipboard") {
            AgentService.clearSttTarget();
        } else if (_targetWindowPid > 0 && AgentService.bridgeRunning) {
            const agent = AgentService.agentForTerminal(_targetWindowPid);
            if (agent) AgentService.setSttTarget(_targetWindowPid, agent.buf ?? -1);
        }
    }

    Component.onDestruction: {
        _stopAllTimers();
        if (recordProcess.running) recordProcess.signal(9);
        if (levelMonitorProcess.running) levelMonitorProcess.running = false;
        if (transcribeProcess.running) transcribeProcess.signal(9);
        if (concatProcess.running) concatProcess.signal(9);
        if (clipboardProcess.running) clipboardProcess.running = false;
        if (injectProcess.running) injectProcess.running = false;
    }
}
