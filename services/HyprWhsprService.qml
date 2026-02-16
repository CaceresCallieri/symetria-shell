pragma Singleton

import qs.config
import qs.utils
import Quickshell
import Quickshell.Io
import QtQuick

/// HyprWhspr speech-to-text orchestrator service.
///
/// Centralizes all HyprWhspr control through IPC, replacing the previous
/// file-based sideband protocol. Keybindings route through Symmetria IPC
/// instead of calling HyprWhspr directly.
///
/// FIFO protocol (long_form recording mode):
/// - "start" / "start:lang"  → Start recording or resume from pause
/// - "stop"                  → Pause (save current segment)
/// - "submit"                → Stop + transcribe all segments
///
/// State transitions (from visualizer_state file):
/// - recording: User is speaking
/// - paused: Recording paused
/// - processing: Transcribing audio
/// - error: Transcription failed
/// - success: Transcription complete
/// - (file deleted): Idle state
///
/// Uses inotifywait for efficient file watching instead of polling.
Singleton {
    id: root

    // Valid HyprWhspr states (file content values)
    readonly property var validStates: ["recording", "paused", "processing", "error", "success"]

    /// Current state: "idle", "recording", "paused", "processing", "error", "success"
    readonly property string state: validStates.includes(_rawState) ? _rawState : "idle"

    // Internal: raw state string from visualizer_state file
    property string _rawState: ""

    /// Audio level (0.0-1.0) during recording
    property real audioLevel: 0.0

    /// Whether any non-idle state is active (used to show/hide drawer).
    /// Requires both a non-idle daemon state AND an orchestrator-initiated session.
    /// This prevents phantom recordings from showing the drawer.
    readonly property bool active: state !== "idle" && _orchestratorActive

    /// Whether currently recording (for audio level polling)
    readonly property bool recording: state === "recording"

    /// Current speech-to-text language code (e.g., "en", "es").
    /// Set via IPC start/toggle calls.
    readonly property string language: _currentLanguage
    property string _currentLanguage: ""

    // Language saved for restart (cancel clears _currentLanguage, but restart needs it)
    property string _pendingRestartLang: ""

    // ─────────────────────────────────────────────────────────────────────────
    // Error detail properties for the drawer UI
    //
    // When the state transitions to "error", these provide categorized
    // information instead of just "Failed". For daemon errors, journalctl
    // is queried. For Symmetria-internal errors (timeout, FIFO, restart),
    // the source is known and journalctl is skipped.
    // ─────────────────────────────────────────────────────────────────────────
    readonly property string errorDetail: _errorDetail
    readonly property string errorHint: _errorHint
    readonly property string errorRaw: _errorRaw

    property string _errorDetail: ""
    property string _errorHint: ""
    property string _errorSource: ""  // "daemon", "timeout", "fifo", "restart"
    property string _errorRaw: ""     // Raw journalctl line (for copy-to-clipboard)

    // Orchestrator-initiated session flag.
    // True only when Symmetria explicitly started a recording session via IPC.
    // Gates the `active` property to prevent phantom recordings (daemon writes
    // "recording" to visualizer_state on startup without any FIFO command).
    property bool _orchestratorActive: false

    /// Emitted when an action is successfully dispatched (not a no-op).
    /// Used by Content.qml to animate the corresponding control button.
    signal actionTriggered(string action)

    // ─────────────────────────────────────────────────────────────────────────
    // Elapsed time tracking (mirrors GTK implementation's timer logic)
    // ─────────────────────────────────────────────────────────────────────────

    /// Elapsed recording time in seconds (updated by timer during recording)
    readonly property real elapsedSeconds: _currentElapsed

    // Internal: current elapsed time (computed by timer, not on every property access)
    property real _currentElapsed: 0

    // Internal: timestamp when current recording segment started (0 if not recording)
    property real _recordingStartTime: 0

    // Internal: accumulated seconds from previous recording segments (for pause/resume)
    property real _accumulatedSeconds: 0

    // Timer interval for elapsed time updates (250ms ensures we catch second
    // boundaries within imperceptible delay, avoiding "0.99 floors to 0" problem)
    readonly property int _elapsedTimerInterval: 250

    // Auto-hide delay constraints (ms)
    readonly property int _minAutoHideDelay: 500    // Minimum: enough time to see success indicator
    readonly property int _maxAutoHideDelay: 10000  // Maximum: prevent indefinite display blocking UI

    // Timer to update _currentElapsed during recording
    Timer {
        id: elapsedTimer
        interval: root._elapsedTimerInterval
        repeat: true
        running: root.recording
        onTriggered: root._currentElapsed = root._accumulatedSeconds + (Date.now() - root._recordingStartTime) / 1000
    }

    // Config directory for HyprWhspr
    readonly property string configDir: `${Paths.home}/.config/hyprwhspr`

    // Control FIFO for sending commands
    readonly property string controlFifo: `${configDir}/recording_control`

    // ─────────────────────────────────────────────────────────────────────────
    // Command queue and FIFO write tracking
    // ─────────────────────────────────────────────────────────────────────────

    property var _commandQueue: []
    property string _lastCommand: ""

    // ─────────────────────────────────────────────────────────────────────────
    // Toggle debouncing
    // ─────────────────────────────────────────────────────────────────────────

    property real _lastToggleTime: 0
    readonly property int _toggleDebounceMs: 200

    // ─────────────────────────────────────────────────────────────────────────
    // Restart retry tracking
    // ─────────────────────────────────────────────────────────────────────────

    property int _restartRetries: 0
    readonly property int _maxRestartRetries: 3

    // ─────────────────────────────────────────────────────────────────────────
    // Orchestrator commands
    //
    // All keybindings route through these functions via IPC. The FIFO protocol
    // requires long_form recording mode in HyprWhspr config.
    // ─────────────────────────────────────────────────────────────────────────

    /// Toggle recording: start if idle, submit if active, recover from error.
    /// This is the primary keybinding action.
    /// When _orchestratorActive is false, any daemon state is treated as phantom
    /// and we start a fresh session regardless of what the daemon reports.
    function toggle(lang: string): void {
        const now = Date.now();
        if (now - _lastToggleTime < _toggleDebounceMs) return;
        _lastToggleTime = now;

        if (state === "idle" || !_orchestratorActive) {
            start(lang);
        } else if (state === "recording" || state === "paused") {
            stop();
        } else if (state === "error") {
            _pendingRestartLang = lang || _currentLanguage || "";
            restart();
        }
    }

    /// Sanitize and validate language codes. Only allow [a-zA-Z-], length 2-5.
    function _sanitizeLanguage(lang: string): string {
        if (!lang) return "";
        const sanitized = lang.replace(/[^a-zA-Z-]/g, "");
        if (sanitized.length < 2 || sanitized.length > 5) {
            console.warn("[HW] Invalid language code:", lang);
            return "";
        }
        return sanitized;
    }

    /// Transition to error state with categorized details.
    /// Centralizes the "set error props before _rawState" pattern so callers
    /// can't accidentally forget the ordering.
    function _setErrorState(source: string, detail: string, hint: string): void {
        _errorSource = source;
        _errorDetail = detail;
        _errorHint = hint;
        _rawState = "error";
    }

    /// Categorize a raw journalctl error line into user-friendly detail + hint.
    /// Pattern matching is ordered from most specific to most general.
    function _categorizeError(rawLine: string): void {
        _errorRaw = rawLine;

        const patterns = [
            { re: /TimeoutError|timed out/i,            detail: "Connection timed out",    hint: "Check your network connection" },
            { re: /ConnectionResetError|Connection reset/i, detail: "Connection reset",    hint: "Server closed the connection" },
            { re: /SSLError|SSL:/i,                     detail: "SSL/TLS error",           hint: "Check API endpoint configuration" },
            { re: /status 401|API key/i,                detail: "Authentication failed",   hint: "Check your API key" },
            { re: /status 429|quota/i,                  detail: "Quota exceeded",          hint: "Check your API plan limits" },
            { re: /status 4\d\d/,                       detail: "API request rejected",    hint: "Check hyprwhspr configuration" },
            { re: /status 5\d\d/,                       detail: "API server error",        hint: "Try again later" },
        ];

        for (const p of patterns) {
            if (p.re.test(rawLine)) {
                _errorDetail = p.detail;
                _errorHint = p.hint;
                return;
            }
        }

        // No pattern matched — keep generic fallback
        _errorDetail = "Transcription failed";
        _errorHint = "Check hyprwhspr logs";
    }

    /// Start recording with optional language code.
    /// Sends "start:lang" or "start" to the FIFO.
    /// Clears stale terminal states and resets elapsed time if overriding phantom state.
    function start(lang: string): void {
        const safeLang = _sanitizeLanguage(lang);
        const cmd = safeLang ? `start:${safeLang}` : "start";

        // Clear stale terminal states from previous daemon crashes
        if (state === "error" || state === "success") {
            _errorSource = "";
            _errorDetail = "";
            _errorHint = "";
            _errorRaw = "";
            _rawState = "";
        }

        _orchestratorActive = true;

        // If daemon already has "recording" state (phantom), reset elapsed time
        // so the drawer shows 00:00 from when the user actually pressed the key
        if (state === "recording") {
            _recordingStartTime = Date.now();
            _accumulatedSeconds = 0;
            _currentElapsed = 0;
        }

        if (safeLang)
            _currentLanguage = safeLang;
        writeCommand(cmd);
    }

    /// Stop recording and submit for transcription.
    /// In long-form mode, FIFO "submit" = stop + transcribe all segments.
    function stop(): void {
        actionTriggered("stop");
        writeCommand("submit");
    }

    /// Toggle pause: pause if recording, resume if paused.
    /// Designed for single-key "Pause/Resume" keybinding.
    function pause(): void {
        if (state === "recording") {
            actionTriggered("pause");
            writeCommand("stop");
        } else if (state === "paused") {
            actionTriggered("resume");
            resume();
        }
    }

    /// Resume from pause. Reuses the stored language code.
    function resume(): void {
        const safeLang = _sanitizeLanguage(_currentLanguage);
        const cmd = safeLang ? `start:${safeLang}` : "start";
        writeCommand(cmd);
    }

    /// Cancel recording: restart HyprWhspr daemon, discard all audio.
    /// Immediately hides the drawer and resets all internal state.
    function cancel(): void {
        actionTriggered("cancel");
        _cancelInternal();
    }

    // Internal cancel logic shared by cancel() and restart().
    // Does NOT emit actionTriggered to avoid double-animation when restart() calls it.
    function _cancelInternal(): void {
        // Stop all timers to prevent post-cancel side effects
        _stopAllTimers();

        _orchestratorActive = false;
        _rawState = "";
        _currentLanguage = "";
        _pendingRestartLang = "";  // Clear pending restart language
        _recordingStartTime = 0;
        _accumulatedSeconds = 0;
        _currentElapsed = 0;
        audioLevel = 0.0;
        _errorSource = "";
        _errorDetail = "";
        _errorHint = "";
        _errorRaw = "";
        cancelProcess.running = true;
    }

    /// Restart recording: cancel current session and start a new one.
    /// Saves the current language so it persists across the restart.
    function restart(): void {
        actionTriggered("restart");

        // Always capture current language (prefer active session, then pending)
        const savedLang = _currentLanguage || _pendingRestartLang || "";

        // Stop any pending restart timer to prevent race with previous restart
        restartDelayTimer.stop();

        _cancelInternal();
        _pendingRestartLang = savedLang;

        restartDelayTimer.start();
    }

    function writeCommand(cmd: string): void {
        if (commandProcess.running) {
            _commandQueue.push(cmd);
            return;
        }
        _executeCommand(cmd);
    }

    function _executeCommand(cmd: string): void {
        _lastCommand = cmd;
        commandProcess.command = ["sh", "-c", "test -p \"$2\" && printf '%s\\n' \"$1\" > \"$2\" || { echo \"FIFO not found: $2\" >&2; exit 1; }", "--", cmd, controlFifo];
        commandProcess.running = true;
    }

    /// Stop all recurring/delay timers (used by cancel and destruction).
    function _stopAllTimers(): void {
        successTimer.stop();
        restartDelayTimer.stop();
        processingTimeoutTimer.stop();
        errorQueryTimeout.stop();
        if (errorQueryProcess.running) errorQueryProcess.running = false;
    }

    // Track if audio_level file exists (only present when visualizer daemon runs)
    property bool _audioLevelExists: false

    // Track if inotifywait failed (e.g., not installed)
    property bool _inotifyFailed: false

    // Visualizer state file reader - the source of truth for HyprWhspr state
    FileView {
        id: visualizerStateFile

        path: `${root.configDir}/visualizer_state`
        watchChanges: false  // We use inotifywait instead

        onLoaded: {
            const newState = text().trim();
            if (root._rawState !== newState) {
                root._rawState = newState;
            }
        }
        onLoadFailed: err => {
            root._rawState = "";
        }
    }

    // Audio level file reader (only used when visualizer daemon is running)
    FileView {
        id: audioLevelFile

        path: `${root.configDir}/audio_level`
        watchChanges: false  // We use inotifywait instead

        onLoaded: {
            const content = text().trim();
            root._audioLevelExists = true;

            // Validate format: should be a short numeric string
            if (content.length === 0 || content.length > 10) {
                return;
            }

            const level = parseFloat(content);
            if (!isNaN(level) && isFinite(level)) {
                root.audioLevel = Math.max(0, Math.min(1, level));
            }
        }
        onLoadFailed: err => {
            root._audioLevelExists = false;
        }
    }

    // inotifywait process to watch the config directory for file changes
    // This is MUCH more efficient than polling
    Process {
        id: inotifyWatcher

        command: [
            "inotifywait",
            "-m",           // Monitor continuously
            "-q",           // Quiet (no initial watching message)
            "-e", "create,delete,modify,moved_to,moved_from",
            "--format", "%f %e",
            root.configDir
        ]

        running: true

        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                const parts = line.split(" ");
                const filename = parts[0];
                const event = parts.slice(1).join(" ");

                if (filename === "visualizer_state") {
                    if (event.includes("DELETE") || event.includes("MOVED_FROM")) {
                        root._rawState = "";
                    } else {
                        visualizerStateFile.reload();
                    }
                } else if (filename === "audio_level") {
                    if (event.includes("DELETE") || event.includes("MOVED_FROM")) {
                        root._audioLevelExists = false;
                    } else {
                        root._audioLevelExists = true;
                        if (root.recording) {
                            audioLevelFile.reload();
                        }
                    }
                } else if (filename === "recording_control") {
                    // Ignore FIFO events (we write to it, not read from it)
                }
            }
        }

        onExited: (code, status) => {
            if (code === 127) {
                console.error("[HW] inotifywait not installed - drawer disabled");
                console.error("  Install with: paru -S inotify-tools");
                root._inotifyFailed = true;
                inotifyWatcher.running = false;
                return;
            }

            if (code !== 0 && !root._inotifyFailed) {
                console.warn("[HW] inotifywait crashed, restarting in 1s");
                inotifyRestartTimer.start();
            }
        }
    }

    // Timer to restart inotifywait if it crashes
    Timer {
        id: inotifyRestartTimer
        interval: 1000
        onTriggered: {
            inotifyWatcher.running = true;
        }
    }

    // Audio level polling during recording
    Timer {
        id: audioLevelPoll

        interval: 33  // ~30fps (sufficient for speech visualization)
        repeat: true
        running: root.recording && root._audioLevelExists

        onTriggered: audioLevelFile.reload()
    }

    // Handle recording state transitions
    onRecordingChanged: {
        if (recording) {
            if (!_audioLevelExists) {
                audioLevelFile.reload();
            }
        } else {
            audioLevel = 0.0;
        }
    }

    // Handle state transitions
    onStateChanged: {
        // Elapsed time tracking
        if (state === "recording") {
            processingTimeoutTimer.stop();
            if (_recordingStartTime === 0) {
                _recordingStartTime = Date.now();
                _currentElapsed = _accumulatedSeconds;
            }
        } else if (state === "paused") {
            processingTimeoutTimer.stop();
            if (_recordingStartTime > 0) {
                _accumulatedSeconds += (Date.now() - _recordingStartTime) / 1000;
                _recordingStartTime = 0;
            } else {
                console.warn("[HW] elapsed: pause without active recording");
            }
        } else if (state === "processing") {
            if (_recordingStartTime > 0) {
                _accumulatedSeconds += (Date.now() - _recordingStartTime) / 1000;
                _currentElapsed = _accumulatedSeconds;
                _recordingStartTime = 0;
            }
            processingTimeoutTimer.start();
        } else {
            // Terminal states (error, success, idle): reset timer
            processingTimeoutTimer.stop();
            _recordingStartTime = 0;
            _accumulatedSeconds = 0;
            _currentElapsed = 0;
            if (state === "idle") {
                _orchestratorActive = false;
            }
            if (state !== "success") {
                _currentLanguage = "";
            }

            // Error detail management
            if (state === "error") {
                // If _errorSource is already set, a Symmetria-internal error
                // populated the details before setting _rawState — skip journalctl.
                if (_errorSource === "") {
                    _errorSource = "daemon";
                    _errorDetail = "Transcription failed";
                    _errorHint = "Fetching error details...";
                    errorQueryProcess.running = true;
                    errorQueryTimeout.start();
                }
            } else {
                // Non-error terminal state: clear stale error details and
                // stop any in-flight journalctl query to prevent race condition
                if (errorQueryProcess.running) errorQueryProcess.running = false;
                errorQueryTimeout.stop();
                _errorSource = "";
                _errorDetail = "";
                _errorHint = "";
                _errorRaw = "";
            }
        }

        if (state === "success") {
            successTimer.start();
        } else {
            successTimer.stop();
        }
    }

    // Timer to auto-hide after success state
    Timer {
        id: successTimer

        interval: {
            const delay = Config.hyprwhspr?.autoHideDelay ?? 1500;
            const clamped = Math.max(root._minAutoHideDelay, Math.min(root._maxAutoHideDelay, delay));
            if (clamped !== delay) {
                console.warn(`[HW] autoHideDelay ${delay}ms clamped to ${clamped}ms`);
            }
            return clamped;
        }

        onTriggered: {
            if (root.state === "success") {
                root._rawState = "";
            }
        }
    }

    // Timer to detect stuck processing state (daemon crash during transcription)
    Timer {
        id: processingTimeoutTimer
        interval: Config.hyprwhspr?.processingTimeout ?? 120000

        onTriggered: {
            console.error("[HW] processingTimeoutTimer: processing timed out — daemon may have crashed");
            root._setErrorState("timeout", "Processing timed out", "Daemon may have crashed");
        }
    }

    // Process for writing commands to control FIFO
    Process {
        id: commandProcess

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.error("[HW] FIFO write failed (exit", exitCode + ") cmd:", root._lastCommand);
                // Rollback orchestrator state if start command failed
                if (root._lastCommand.startsWith("start")) {
                    root._orchestratorActive = false;
                    root._currentLanguage = "";
                    root._setErrorState("fifo", "Failed to send command", "Is hyprwhspr running?");
                }
            }

            // Process queued commands
            if (root._commandQueue.length > 0) {
                const nextCmd = root._commandQueue.shift();
                root._executeCommand(nextCmd);
            }
        }
    }

    // Process for restarting the HyprWhspr systemd service (used by cancel/restart)
    Process {
        id: cancelProcess
        command: ["systemctl", "--user", "restart", "hyprwhspr"]

        onExited: (code, status) => {
            if (code !== 0) {
                console.error("[HW] systemd restart failed (exit", code + ")");
                root._setErrorState("restart", "Service restart failed", "Check systemctl --user status hyprwhspr");
            }
        }
    }

    // Timer for delayed start after cancel (used by restart).
    // Waits for the daemon to come back up before sending start command.
    Timer {
        id: restartDelayTimer
        interval: Config.hyprwhspr?.restartDelay ?? 500

        onTriggered: {
            if (root._pendingRestartLang === "") return;
            restartProbeProcess.running = true;
        }
    }

    // Probe process to check if FIFO exists before restarting
    Process {
        id: restartProbeProcess
        command: ["test", "-p", root.controlFifo]

        onExited: (code, status) => {
            if (code === 0) {
                const lang = root._pendingRestartLang;
                root._pendingRestartLang = "";
                root._restartRetries = 0;
                root.start(lang);
            } else if (root._restartRetries < root._maxRestartRetries) {
                root._restartRetries++;
                console.warn("[HW] Daemon not ready, retry", root._restartRetries, "/", root._maxRestartRetries);
                restartDelayTimer.start();
            } else {
                console.error("[HW] Restart failed after", root._maxRestartRetries, "retries");
                root._pendingRestartLang = "";
                root._restartRetries = 0;
                root._setErrorState("restart", "Daemon not responding", "Try restarting hyprwhspr manually");
            }
        }
    }

    // Process for querying recent HyprWhspr errors from journalctl.
    // Triggered when daemon reports "error" and _errorSource is empty (unknown cause).
    // Uses -p err to filter error-level messages, -o cat for clean output.
    Process {
        id: errorQueryProcess

        command: ["journalctl", "--user-unit=hyprwhspr", "--no-pager", "-n", "5", "--since", "-2min", "-p", "err", "-o", "cat"]

        onExited: (code, status) => {
            errorQueryTimeout.stop();
            if (code !== 0) {
                console.warn("[HW] journalctl query failed (exit", code, ") — using generic error");
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                errorQueryTimeout.stop();

                if (!text || text.trim() === "") {
                    // No error lines found in journal
                    root._errorHint = "No details in journal (check daemon logs)";
                    return;
                }

                // Find the last ERROR line (most recent is most relevant)
                const lines = text.trim().split("\n");
                let errorLine = "";
                for (let i = lines.length - 1; i >= 0; i--) {
                    if (lines[i].includes("ERROR")) {
                        errorLine = lines[i];
                        break;
                    }
                }

                if (errorLine) {
                    root._categorizeError(errorLine);
                } else {
                    // Journalctl returned lines but none had "ERROR" — use last line as raw
                    root._categorizeError(lines[lines.length - 1]);
                }
            }
        }
    }

    // Timeout for journalctl error query — prevents "Fetching error details..."
    // from displaying indefinitely if journalctl hangs or is very slow.
    Timer {
        id: errorQueryTimeout
        interval: 5000

        onTriggered: {
            if (errorQueryProcess.running) {
                console.warn("[HW] Error query timed out — using generic message");
                errorQueryProcess.running = false;
            }
        }
    }

    // Orphan detection: if daemon reports recording/paused but orchestrator didn't start it
    Timer {
        id: orphanDetectionTimer
        interval: 500
        onTriggered: {
            if ((root.state === "recording" || root.state === "paused") && !root._orchestratorActive) {
                console.warn("[HW] Detected orphaned recording session — auto-adopting");
                root._orchestratorActive = true;
                root._recordingStartTime = Date.now();
            }
        }
    }

    // Initial state check - inotifywait only fires on CHANGES, not initial state.
    // If recording is already in progress when shell starts, we need to check files directly.
    Component.onCompleted: {
        visualizerStateFile.reload();
        audioLevelFile.reload();
        orphanDetectionTimer.start();
    }

    // Cleanup on destruction
    Component.onDestruction: {
        _stopAllTimers();
        audioLevelPoll.stop();
        inotifyWatcher.running = false;
    }
}
