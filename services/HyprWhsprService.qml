pragma Singleton

import qs.config
import qs.utils
import Quickshell
import Quickshell.Io
import QtQuick

/// HyprWhspr speech-to-text service.
///
/// Watches HyprWhspr's visualizer_state file for state transitions:
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

    /// Whether HyprWhspr is available (service is running)
    readonly property bool available: true

    /// Whether any non-idle state is active (used to show/hide drawer)
    readonly property bool active: state !== "idle"

    /// Whether currently recording (for audio level polling)
    readonly property bool recording: state === "recording"

    // Config directory for HyprWhspr
    readonly property string configDir: `${Paths.home}/.config/hyprwhspr`

    // Control FIFO for sending commands
    readonly property string controlFifo: `${configDir}/recording_control`

    /// Send start command to HyprWhspr
    function start(): void {
        writeCommand("start");
    }

    /// Send stop command to HyprWhspr
    function stop(): void {
        writeCommand("stop");
    }

    /// Pause recording
    function pause(): void {
        writeCommand("pause");
    }

    /// Resume recording
    function resume(): void {
        writeCommand("resume");
    }

    function writeCommand(cmd: string): void {
        commandProcess.command = ["sh", "-c", `printf '%s\\n' '${cmd}' > '${controlFifo}'`];
        commandProcess.running = true;
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
                console.log("HyprWhspr: visualizer_state =", newState);
                root._rawState = newState;
            }
        }
        onLoadFailed: err => {
            // File deletion means return to idle - this is normal
            if (root._rawState !== "") {
                console.log("HyprWhspr: visualizer_state deleted (idle)");
            }
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
                        // File was deleted - return to idle
                        if (root._rawState !== "") {
                            console.log("HyprWhspr: visualizer_state deleted (idle)");
                        }
                        root._rawState = "";
                    } else {
                        // File was created or modified - read new state
                        visualizerStateFile.reload();
                    }
                } else if (filename === "audio_level") {
                    // Always track file existence, regardless of recording state.
                    // This avoids the race condition where recording=true but
                    // _audioLevelExists=false because events arrived in the wrong order.
                    if (event.includes("DELETE") || event.includes("MOVED_FROM")) {
                        root._audioLevelExists = false;
                    } else {
                        root._audioLevelExists = true;
                        // Only read content if we're actually recording (saves I/O)
                        if (root.recording) {
                            audioLevelFile.reload();
                        }
                    }
                }
            }
        }

        onExited: (code, status) => {
            // Exit code 127 = command not found (inotifywait not installed)
            if (code === 127) {
                console.error("HyprWhspr: inotifywait not installed - drawer disabled");
                console.error("  Install with: paru -S inotify-tools");
                root._inotifyFailed = true;
                inotifyWatcher.running = false;  // Explicitly stop to prevent respawn attempts
                return;
            }

            // Restart if it exits unexpectedly
            if (code !== 0 && !root._inotifyFailed) {
                console.warn("HyprWhspr: inotifywait exited with code", code, "- restarting");
                restartTimer.start();
            }
        }
    }

    // Timer to restart inotifywait if it crashes
    Timer {
        id: restartTimer
        interval: 1000
        onTriggered: inotifyWatcher.running = true
    }

    // Audio level polling during recording (60fps for smooth visualizations).
    // We use polling here instead of inotifywait because:
    // 1. Audio level updates need ~60fps for smooth bar animations
    // 2. inotifywait event batching would cause stuttering
    // 3. FileView.reload() is fast for small files (<10 bytes)
    // 4. Only runs when recording AND audio_level file exists
    Timer {
        id: audioLevelPoll

        interval: 16  // ~60fps
        repeat: true
        running: root.recording && root._audioLevelExists

        onTriggered: audioLevelFile.reload()
    }

    // Handle recording state transitions
    onRecordingChanged: {
        if (recording) {
            // Proactively check for audio_level file when recording starts.
            // This handles the race condition where audio_level file was created
            // BEFORE visualizer_state changed to "recording". The inotifywait event
            // for audio_level may have arrived first, setting _audioLevelExists=true,
            // but the 60fps polling timer wasn't running yet (requires recording=true).
            // This one-time check ensures we don't miss the initial audio level.
            if (!_audioLevelExists) {
                audioLevelFile.reload();
            }
        } else {
            audioLevel = 0.0;
        }
    }

    // Handle state transitions
    onStateChanged: {
        console.log("HyprWhspr: State changed to:", state);

        // Start auto-hide timer on success
        if (state === "success") {
            successTimer.start();
        } else {
            successTimer.stop();
        }
    }

    // Timer to auto-hide after success state
    // HyprWhspr may keep success state for a while, so we force return to idle
    // after showing the success indicator
    Timer {
        id: successTimer

        // Validate autoHideDelay: clamp to 500ms-10s range
        interval: {
            const delay = Config.hyprwhspr?.autoHideDelay ?? 1500;
            const clamped = Math.max(500, Math.min(10000, delay));
            if (clamped !== delay) {
                console.warn(`HyprWhspr: autoHideDelay ${delay}ms clamped to ${clamped}ms (valid: 500-10000)`);
            }
            return clamped;
        }

        onTriggered: {
            // Only hide if still in success state (prevents hiding during rapid transitions)
            if (root.state === "success") {
                root._rawState = "";
            }
        }
    }

    // Process for writing commands to control FIFO
    Process {
        id: commandProcess

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.warn("HyprWhspr: Command failed with exit code:", exitCode);
        }
    }

    // Initial state check - inotifywait only fires on CHANGES, not initial state.
    // If recording is already in progress when shell starts, we need to check files directly.
    // Note: If audio_level file doesn't exist yet, onRecordingChanged will retry when
    // recording state becomes true (see that handler for the fallback logic).
    Component.onCompleted: {
        visualizerStateFile.reload();
        audioLevelFile.reload();
    }

    // Cleanup on destruction
    Component.onDestruction: {
        audioLevelPoll.stop();
        successTimer.stop();
        inotifyWatcher.running = false;
    }
}
