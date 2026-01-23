pragma Singleton

import qs.config
import qs.utils
import Quickshell
import Quickshell.Io
import QtQuick

/// HyprWhspr speech-to-text service.
///
/// Watches HyprWhspr state files (recording_status, audio_level) to detect recording state.
/// Uses inotifywait for efficient file watching instead of polling.
Singleton {
    id: root

    /// Current state: "idle", "recording", "processing"
    readonly property string state: {
        if (_isRecording) {
            return "recording";
        }
        if (_wasRecording) {
            return "processing";
        }
        return "idle";
    }

    // Internal property to track recording status from file
    property bool _isRecording: false

    /// Audio level (0.0-1.0) during recording
    property real audioLevel: 0.0

    /// Whether HyprWhspr is available (service is running)
    readonly property bool available: true

    /// Whether any non-idle state is active (used to show/hide drawer)
    readonly property bool active: state !== "idle"

    /// Whether currently recording (for audio level polling)
    readonly property bool recording: state === "recording"

    // Internal: track if we were recording to detect transition to processing
    property bool _wasRecording: false

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

    /// Cancel recording (same as stop)
    function cancel(): void {
        writeCommand("stop");
    }

    function writeCommand(cmd: string): void {
        commandProcess.command = ["sh", "-c", `echo "${cmd}" > "${controlFifo}"`];
        commandProcess.running = true;
    }

    // Track if audio_level file exists (only present when visualizer daemon runs)
    property bool _audioLevelExists: false

    // Track if inotifywait failed (e.g., not installed)
    property bool _inotifyFailed: false

    // Recording status file reader
    FileView {
        id: recordingStatusFile

        path: `${root.configDir}/recording_status`
        watchChanges: false  // We use inotifywait instead

        onLoaded: {
            const status = text().trim();
            const wasRecording = root._isRecording;
            root._isRecording = (status === "true");
            if (root._isRecording !== wasRecording) {
                console.log("HyprWhspr: recording_status =", status);
            }
        }
        onLoadFailed: err => {
            // File deletion means recording stopped - this is normal
            if (root._isRecording) {
                console.log("HyprWhspr: recording stopped");
            }
            root._isRecording = false;
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

                if (filename === "recording_status") {
                    if (event.includes("DELETE") || event.includes("MOVED_FROM")) {
                        // File was deleted - recording stopped
                        if (root._isRecording) {
                            console.log("HyprWhspr: recording stopped");
                        }
                        root._isRecording = false;
                    } else {
                        // File was created or modified - check content
                        recordingStatusFile.reload();
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
            // This handles timing where the file was created before we detected
            // the recording state change.
            if (!_audioLevelExists) {
                audioLevelFile.reload();
            }
        } else {
            audioLevel = 0.0;
        }
    }

    // Track recording state transitions
    onStateChanged: {
        console.log("HyprWhspr: State changed to:", state);

        if (state === "recording") {
            _wasRecording = true;
        } else if (state === "processing") {
            processingTimer.start();
        } else if (state === "idle") {
            _wasRecording = false;
            processingTimer.stop();
        }
    }

    // Timer to auto-clear processing state
    Timer {
        id: processingTimer

        // Validate autoHideDelay: clamp to 500ms-10s range
        interval: {
            const delay = Config.hyprwhspr?.autoHideDelay ?? 3000;
            return Math.max(500, Math.min(10000, delay));
        }

        onTriggered: {
            root._wasRecording = false;
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
        recordingStatusFile.reload();
        audioLevelFile.reload();
    }

    // Cleanup on destruction
    Component.onDestruction: {
        audioLevelPoll.stop();
        processingTimer.stop();
        inotifyWatcher.running = false;
    }
}
