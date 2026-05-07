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
/// Accesses service-level state (delivery mode, temp dir) through
/// the SttService singleton.
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

    // Whether wl-copy ran during this delivery. Drives the post-paste cliphist
    // scrub: if we put text on the clipboard, cliphist captured it into the
    // Text tab — we delete-query it back out so the Transcriptions tab is
    // the only place STT outputs appear. Only false for RPC-only deliveries
    // that bypass the clipboard entirely.
    property bool _ranWlCopy: false

    // Whether this delivery is clipboard-mode only (no inject chain). When
    // true, clipboardProcess.onExited finalizes the delivery directly:
    // record + scrub + state=success. When false, it chains to
    // _spawnInjectProcess() for the sendshortcut Ctrl+V on a target window.
    property bool _clipboardModeOnly: false

    // Text payload pending cliphist delete-query (after a small delay to let
    // the wl-paste --watch daemon write the entry to its db before we try
    // to remove it). Cleared once the timer fires.
    property string _pendingCliphistDelete: ""

    // Set when _cleanupRecovery() is called while recoveryPersistProcess is
    // still running. The onExited handler re-runs cleanup so a cancel-during-
    // persist race ends with the file absent (honoring the cancel intent)
    // rather than orphaned (rm fires before cp completes).
    property bool _pendingRecoveryCleanup: false

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

    /// Cancel: kill processes, discard audio, trigger removal.
    function cancel(): void {
        cancelForRestart();

        // Clear activeRecording if this job is the active one.
        // NOTE: When called via SttService.cancel(), _activeRecording has
        // already been cleared. This guard only fires when cancel() is called
        // directly on the job (e.g. from RecordingActions.qml cancel button),
        // bypassing the service-level orchestration.
        if (SttService._activeRecording === job)
            SttService._activeRecording = null;

        // Remove from jobs list (via _removeJob so hide animation plays)
        SttService._removeJob(job);
    }

    /// Tear down processes and resources WITHOUT triggering the close
    /// animation or scheduling removal. Used by SttService.restart(), which
    /// wants a seamless atomic swap: _job is kept alive (and closing stays
    /// false) until the new job is ready, at which point _startInternal
    /// reassigns _job and destroys this old job directly. Setting
    /// closing=true here would prematurely trigger Bar.qml's declarative
    /// _showEmbed binding (which is true when !closing), collapsing the embed
    /// without a subsequent re-raise because the binding only re-evaluates
    /// when _job or its closing flag changes — and _job never transitions
    /// back through null in the new restart flow.
    function cancelForRestart(): void {
        _pendingRecordAction = "cancel";
        _stopAllTimers();

        if (recordProcess.running) recordProcess.signal(9);
        if (levelMonitorProcess.running) levelMonitorProcess.running = false;
        if (transcribeProcess.running) transcribeProcess.signal(9);
        if (concatProcess.running) concatProcess.signal(9);

        _cleanupTempFiles();
        // Cancel is a deliberate "throw this away" action — also drop any
        // persistent recovery copy, since the user explicitly discarded it.
        _cleanupRecovery();
        _clearSttTargetIfOwned();
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
    /// Direct-UI entry point — no actionTriggered signal emitted.
    /// For IPC with UI feedback, use SttService.setDeliveryChoice instead.
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

    /// Capture the currently active window for inject / clipboard auto-paste
    /// delivery. Captured at recording-start; subsequent focus changes don't
    /// affect the target. For clipboard mode this gives us the window to
    /// sendshortcut Ctrl+V into; for inject/submit it's the RPC or
    /// sendshortcut target.
    function _captureTargetWindow(): void {
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
    /// Returns true if an auto-retry was scheduled, false if the error
    /// is permanent (shows toast to the user in that case).
    function _tryAutoRetry(): bool {
        if (_autoRetryCount >= _maxAutoRetries || !_isTransientError() || _currentAudioFile === "") {
            Toaster.toast(qsTr("STT: %1").arg(_errorDetail), _errorHint, "error", Toast.Error);
            // Save the audio + metadata so the user can retry after a shell
            // restart. Only fires when no more auto-retries will happen —
            // avoids churn for errors that the service will silently resolve.
            _persistRecovery();
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

    /// Start the delivery chain. Three paths, all routed through
    /// stt-inject.sh except RPC-only (which talks directly to nvim):
    ///
    /// - "clipboard" mode → wl-copy + stt-inject.sh sendshortcut Ctrl+V on
    ///   the captured target window. Always sendshortcut, never RPC, even
    ///   in Claude Code terminals — clipboard mode is intentionally
    ///   agent-unaware. cliphist briefly captures the entry; we scrub it
    ///   in injectProcess onExited.
    ///
    /// - "inject" / "submit" mode + RPC eligible (terminal target with a
    ///   resolved Neovim socket, e.g. Claude Code) → skip wl-copy entirely;
    ///   stt-inject.sh writes directly to the buffer over the RPC socket,
    ///   no clipboard touch. STT_RPC_ONLY=1 tells the script not to fall
    ///   back to sendshortcut (which would need clipboard contents we never
    ///   provided). Recorded in TranscriptionStore on injectProcess exit.
    ///
    /// - "inject" / "submit" mode + non-RPC target (browser, chat, etc.) →
    ///   wl-copy + stt-inject.sh sendshortcut paste. Same flow as clipboard
    ///   mode but the script is allowed to attempt RPC if a socket happens
    ///   to be available.
    function _startDeliveryChain(): void {
        _state = "delivering";

        const effectiveMode = SttService._deliveryMode === "ask"
            ? _activeDeliveryChoice
            : SttService._deliveryMode;
        Logger.log("qml", "stt", "delivery-start | id=" + sessionId + " mode=" + effectiveMode + " textLen=" + _transcribedText.length);

        if (effectiveMode === "clipboard") {
            console.log("[STT:D11] → delivering via wl-copy + sendshortcut (clipboard mode, no RPC) | id:", sessionId, "textLength:", _transcribedText.length);
            _ranWlCopy = true;
            _clipboardModeOnly = true;
            clipboardProcess.command = ["wl-copy", _transcribedText];
            clipboardProcess.running = true;
            return;
        }

        _clipboardModeOnly = false;

        const rpcEligible = _targetWindowAddress !== ""
            && _targetNvimSocket !== ""
            && _isTerminalClass(_targetWindowClass);

        if (rpcEligible) {
            console.log("[STT:D11] → delivering via RPC-only (skipping wl-copy) | id:", sessionId, "textLength:", _transcribedText.length);
            _ranWlCopy = false;
            _spawnInjectProcess(true, false);
        } else {
            console.log("[STT:D11] → delivering via wl-copy + sendshortcut | id:", sessionId, "textLength:", _transcribedText.length);
            _ranWlCopy = true;
            clipboardProcess.command = ["wl-copy", _transcribedText];
            clipboardProcess.running = true;
        }
    }

    /// Whether the given window class is a terminal emulator. Mirrors the
    /// is_terminal_class function in stt-inject.sh — the script's RPC path
    /// only fires for terminal classes, so the QML pre-check must agree
    /// (otherwise we'd skip wl-copy assuming RPC will fire, but the script
    /// would fall through and fail on empty clipboard).
    function _isTerminalClass(cls: string): bool {
        if (!cls) return false;
        const lc = cls.toLowerCase();
        return /(?:ghostty|warp|wezterm|alacritty|kitty|foot|konsole|xterm|urxvt|termite|sakura|tilix|terminator|st-)/.test(lc);
    }

    /// Spawn injectProcess with the right args + env. Three call sites converge
    /// here, distinguished by the (rpcOnly, forceSendshortcut) tuple:
    ///
    ///   (true,  false) — RPC-eligible inject/submit. Script tries RPC; on
    ///                    failure it surfaces an error (no sendshortcut
    ///                    fallback because we never put text on the clipboard).
    ///   (false, false) — Non-RPC inject/submit fallback. wl-copy already ran;
    ///                    script tries RPC if a socket is set, falls through
    ///                    to sendshortcut Ctrl+V otherwise.
    ///   (false, true)  — Clipboard mode auto-paste. wl-copy already ran;
    ///                    socket is blanked out so the script unconditionally
    ///                    uses sendshortcut Ctrl+V (no RPC even if a socket
    ///                    was resolved). This preserves "clipboard mode is
    ///                    agent-unaware" semantics — RPC-style smart routing
    ///                    is reserved for the inject/submit modes.
    function _spawnInjectProcess(rpcOnly: bool, forceSendshortcut: bool): void {
        if (_targetWindowAddress === "") {
            console.log("[STT:D14] inject SKIPPED — no target | id:", sessionId);
            // Still record the transcription so it's reachable via the Transcriptions
            // tab and Alt+V, even though we couldn't deliver to a target window.
            TranscriptionStore.add(job._transcribedText);
            _injectionPath = "";
            _injectionDowngraded = false;
            _injectionSubmitted = false;
            // Schedule cliphist scrub if wl-copy ran — no injectProcess will
            // fire for this path, so we must scrub here. Without this, the
            // transcription entry lingers permanently in the clipboard Text tab.
            if (_ranWlCopy) {
                _pendingCliphistDelete = _transcribedText;
                cliphistDeleteTimer.restart();
            }
            _state = "success";
            return;
        }
        if (_targetWindowClass === "")
            console.warn("[STT:D14] Window class unknown; inject will use Ctrl+V");
        const effectiveMode = SttService._deliveryMode === "ask"
            ? _activeDeliveryChoice
            : SttService._deliveryMode;
        const cmd = [_injectScript, _targetWindowAddress, _targetWindowClass];
        if (effectiveMode === "submit") cmd.push("submit");
        Logger.log("qml", "stt", "inject-start | id=" + sessionId + " target=" + _targetWindowAddress + " rpcOnly=" + rpcOnly + " forceSendshortcut=" + forceSendshortcut);
        // Effective socket: blanked when forcing sendshortcut so the script
        // can't accidentally take the RPC path even if _targetNvimSocket was
        // resolved earlier.
        const effectiveSocket = forceSendshortcut ? "" : _targetNvimSocket;
        // Prepend voice tag for agent-backed terminals (e.g. Claude Code)
        // so the LLM knows the input is voice-transcribed. Suppressed when
        // we're forcing sendshortcut (clipboard mode = no agent awareness).
        const voicePrefix = (Config.stt?.voiceTag && effectiveSocket !== "")
            ? Config.stt?.voiceTag : "";
        injectProcess.environment = ({
            STT_EXPECTED_TEXT: voicePrefix + _transcribedText,
            STT_NVIM_SOCKET: effectiveSocket,
            STT_NVIM_ACTIVE_BUF: forceSendshortcut ? "-1" : _targetNvimActiveBuf.toString(),
            STT_RPC_ONLY: rpcOnly ? "1" : ""
        });
        injectProcess.command = cmd;
        injectProcess.running = true;
    }

    /// Delete temp files for this session.
    function _cleanupTempFiles(): void {
        if (sessionId !== "") {
            Quickshell.execDetached(["find", SttService._tempDir, "-maxdepth", "1",
                "-name", `session_${sessionId}_*`, "-delete"]);
        }
    }

    /// Copy the current audio file to the persistent recovery dir and write
    /// a JSON sidecar alongside it, so the user can retry the transcription
    /// after a shell restart. Also refreshes the `latest.{wav,json}` symlinks
    /// for easy access, and enforces the Config.stt.cache.maxEntries cap by
    /// deleting oldest pairs. Called once per job, only when a final error
    /// has been reached (auto-retries exhausted).
    function _persistRecovery(): void {
        if (sessionId === "" || _currentAudioFile === "") return;
        if (!(Config.stt?.cache?.enabled ?? true)) return;
        if (recoveryPersistProcess.running) return;

        const sidecar = {
            sessionId: sessionId,
            createdAt: new Date().toISOString(),
            audioFile: `session_${sessionId}.wav`,
            vocabHints: _snapshotVocabHints.slice(),
            deliveryMode: SttService._deliveryMode,
            activeDeliveryChoice: _activeDeliveryChoice,
            errorSource: _errorSource,
            errorDetail: _errorDetail,
            errorHint: _errorHint,
            targetWindowClass: _targetWindowClass,
            model: Config.stt?.model ?? "gpt-4o-transcribe"
        };
        // Pass the JSON via base64 to avoid quote-escaping hell in the shell
        // command — the output is ASCII-safe and won't interact with `sh -c`.
        const sidecarB64 = Qt.btoa(JSON.stringify(sidecar, null, 2));
        const maxEntries = Config.stt?.cache?.maxEntries ?? 10;

        recoveryPersistProcess.savedAudioPath = `${SttService._recoveryDir}/session_${sessionId}.wav`;
        recoveryPersistProcess.environment = {
            RECOVERY_DIR: SttService._recoveryDir,
            SRC_AUDIO: _currentAudioFile,
            SESSION_ID: sessionId,
            SIDECAR_B64: sidecarB64,
            MAX_ENTRIES: maxEntries.toString()
        };
        recoveryPersistProcess.running = true;
    }

    /// Remove any persisted recovery copy for this session. Safe to call
    /// unconditionally — `rm -f` swallows missing-file errors. Also cleans
    /// up the `latest.*` symlinks if they pointed at this session, so they
    /// don't dangle after the target is deleted.
    function _cleanupRecovery(): void {
        if (sessionId === "") return;
        // Defer cleanup if persistence is mid-flight — otherwise rm -f may
        // fire before cp completes, leaving an orphan file. onExited calls
        // us back when the persist Process has finished.
        if (recoveryPersistProcess.running) {
            _pendingRecoveryCleanup = true;
            return;
        }
        _pendingRecoveryCleanup = false;
        // Use `env KEY=val ... sh -c` to set shell variables cleanly —
        // avoids embedding sessionId / path in the script body with all
        // the quote-escaping risks that entails.
        Quickshell.execDetached([
            "env",
            "RECOVERY_DIR=" + SttService._recoveryDir,
            "SESSION_ID=" + sessionId,
            "sh", "-c",
            'latest_wav="$RECOVERY_DIR/latest.wav"\n' +
            'latest_json="$RECOVERY_DIR/latest.json"\n' +
            'if [ "$(readlink "$latest_wav" 2>/dev/null)" = "session_$SESSION_ID.wav" ]; then rm -f "$latest_wav" "$latest_json"; fi\n' +
            'rm -f "$RECOVERY_DIR/session_$SESSION_ID.wav" "$RECOVERY_DIR/session_$SESSION_ID.json"\n'
        ]);
    }

    function _stopAllTimers(): void {
        elapsedTimer.stop();
        successTimer.stop();
        processingTimeoutTimer.stop();
        autoRetryTimer.stop();
        _removalTimer.stop();
        cliphistDeleteTimer.stop();
    }

    /// Trigger animated removal — called by SttService orchestrator.
    /// Starts the per-job removal timer so the bar-embed close animation
    /// (via _activeJob.closing in Bar.qml) completes before the job is destroyed.
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

    // Animated removal delay — outlasts the bar-embed close animation in Bar.qml
    readonly property Timer _removalTimer: Timer {
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
                // Mark as transcribed and signal readiness for delivery
                job._state = "transcribed";
                if (Config.stt?.cache?.deleteOnSuccess ?? true)
                    job._cleanupTempFiles();
                // Always clean up any persistent recovery copy on success —
                // the user clearly didn't need it. Safe even if nothing was
                // persisted (rm -f swallows missing-file errors).
                job._cleanupRecovery();
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

    // wl-copy delivery for clipboard mode and inject/submit non-RPC fallback.
    // Both paths chain to _spawnInjectProcess() afterwards; the difference is
    // the forceSendshortcut flag — clipboard mode forces sendshortcut Ctrl+V
    // (no RPC), inject/submit lets the script attempt RPC if a socket is set.
    // injectProcess.onExited handles record + scrub + state. RPC-eligible
    // inject/submit deliveries bypass this Process entirely.
    readonly property Process clipboardProcess: Process {
        onExited: (code, status) => {
            Logger.log("qml", "stt", "clipboard-done | id=" + job.sessionId + " code=" + code + " clipboardOnly=" + job._clipboardModeOnly);
            if (code !== 0) {
                console.error("[STT:D12] wl-copy FAILED (exit", code + ")");
                // Record so the entry is reachable from Transcriptions / Alt+V
                // even if wl-copy itself failed in this particular run.
                // _injectionPath/_Down/_Submitted keep their defaults — this job
                // is freshly created and no inject step ran.
                TranscriptionStore.add(job._transcribedText);
                job._state = "success";
                return;
            }
            // forceSendshortcut === _clipboardModeOnly: clipboard mode forces
            // sendshortcut Ctrl+V (no RPC); non-RPC inject/submit lets the
            // script attempt RPC if a socket is set. injectProcess.onExited
            // finalizes both paths (record + scrub + state).
            job._spawnInjectProcess(false, job._clipboardModeOnly);
        }
    }

    // Persist audio + sidecar to the recovery dir after a final error.
    // All filesystem work happens inside a single `sh -c` script so the
    // steps are ordered (mkdir → cp → sidecar → symlink → cap-enforce)
    // without needing to chain multiple Processes.
    readonly property Process recoveryPersistProcess: Process {
        property string savedAudioPath: ""
        command: [
            "sh", "-c",
            'set -e\n' +
            'mkdir -p "$RECOVERY_DIR"\n' +
            'cp -f "$SRC_AUDIO" "$RECOVERY_DIR/session_$SESSION_ID.wav"\n' +
            'printf \'%s\' "$SIDECAR_B64" | base64 -d > "$RECOVERY_DIR/session_$SESSION_ID.json"\n' +
            'ln -sfn "session_$SESSION_ID.wav" "$RECOVERY_DIR/latest.wav"\n' +
            'ln -sfn "session_$SESSION_ID.json" "$RECOVERY_DIR/latest.json"\n' +
            // Evict oldest sidecar+audio pairs when over maxEntries. `ls -t`
            // lists newest-first; tailing from MAX+1 gives us just the
            // overflow, then we delete each .json with its matching .wav.
            'ls -t "$RECOVERY_DIR"/session_*.json 2>/dev/null | tail -n +$((MAX_ENTRIES + 1)) | while read -r f; do rm -f "$f" "${f%.json}.wav"; done\n'
        ]
        onExited: (code, status) => {
            if (code === 0) {
                Logger.log("qml", "stt", "recovery-saved | id=" + job.sessionId + " path=" + savedAudioPath);
                Toaster.toast(
                    qsTr("STT: Recording saved for recovery"),
                    savedAudioPath,
                    "save",
                    Toast.Warning
                );
            } else {
                Logger.log("qml", "stt", "recovery-persist-failed | id=" + job.sessionId + " code=" + code);
                console.error("[STT:D21] Recovery persist failed (exit", code + ")");
            }
            // Honor a cancel that arrived while persistence was in flight.
            if (job._pendingRecoveryCleanup)
                job._cleanupRecovery();
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
                "| code:", code, "| path:", job._injectionPath, "| ranWlCopy:", job._ranWlCopy);
            if (code !== 0)
                console.warn("[STT:D16] inject script FAILED (code", code + ") — non-fatal");

            // Single funnel for "delivery complete":
            //   1. Record in TranscriptionStore (so the entry is reachable
            //      from the Transcriptions tab and Alt+V regardless of
            //      whether this delivery's inject step succeeded — text
            //      may still be useful for re-paste).
            //   2. If wl-copy ran, schedule a delayed cliphist delete-query
            //      to scrub the entry from the Text tab. The delay (300 ms)
            //      lets the wl-paste --watch daemon write the entry to
            //      cliphist's db before we try to remove it. The
            //      Transcriptions tab is unaffected — different store.
            TranscriptionStore.add(job._transcribedText);
            if (job._ranWlCopy) {
                job._pendingCliphistDelete = job._transcribedText;
                job.cliphistDeleteTimer.restart();
            }
            job._state = "success";
        }
    }

    // Delayed cliphist scrub. The wl-paste --watch daemon that backs
    // cliphist writes captured entries to its db asynchronously (~tens of
    // ms after the wl-copy change event). Firing delete-query immediately
    // would race against that write. 300ms is comfortably above the
    // observed capture latency without making the entry visible long
    // enough for a human to notice in the Text tab.
    readonly property Timer cliphistDeleteTimer: Timer {
        interval: 300
        onTriggered: {
            if (job._pendingCliphistDelete === "") return;
            Logger.log("qml", "stt", "cliphist-scrub | id=" + job.sessionId + " textLen=" + job._pendingCliphistDelete.length);
            Quickshell.execDetached(["cliphist", "delete-query", job._pendingCliphistDelete]);
            job._pendingCliphistDelete = "";
        }
    }
}
