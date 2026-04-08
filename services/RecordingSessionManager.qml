pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import Quickshell
import Symmetria
import QtQuick

/// Coordinator singleton for mutual exclusivity between recording modes
/// (STT and Audio Recorder).
///
/// Does NOT own services — only gates entry via acquire/release and routes
/// shared keybind actions (pause, cancel, stop) to whichever service is active.
///
/// Pattern: each service calls acquire() before starting; the manager
/// auto-releases when the service deactivates (prevents stale locks).
Singleton {
    id: root

    // ── Public properties ──────────────────────────────────────────

    /// Which recording mode holds the lock: "stt", "audio", or "" (none)
    readonly property string activeMode: _activeMode

    /// Whether any recording mode is active
    readonly property bool active: _activeMode !== ""

    // ── Internal state ─────────────────────────────────────────────

    property string _activeMode: ""

    readonly property var _modeNames: ({
        "stt": qsTr("Speech-to-Text"),
        "audio": qsTr("Audio Recorder")
    })

    /// Shared icon names for STT delivery modes. Used by Content.qml and RecordingBarEmbed.qml.
    readonly property var deliveryModeIcons: ({
        "clipboard": "content_copy",
        "inject": "input",
        "submit": "send"
    })

    // ── Public methods ─────────────────────────────────────────────

    /// Attempt to acquire the recording lock for a mode.
    /// Returns true if acquired, false if blocked (shows toast).
    function acquire(mode: string): bool {
        if (_activeMode === "" || _activeMode === mode) {
            _activeMode = mode;
            return true;
        }

        // Blocked — show user feedback
        const activeName = _modeNames[_activeMode] ?? _activeMode;
        const requestedName = _modeNames[mode] ?? mode;
        Toaster.toast(
            qsTr("%1 is active").arg(activeName),
            qsTr("Cancel it before starting %1").arg(requestedName),
            "block",
            Toast.Warning
        );
        return false;
    }

    /// Release the recording lock for a mode.
    /// No-op if the mode doesn't hold the lock.
    function release(mode: string): void {
        if (_activeMode === mode)
            _activeMode = "";
    }

    /// Route a shared action to whichever service is active.
    function routeAction(action: string): void {
        if (_activeMode === "stt") {
            switch (action) {
                case "pause": SttService.pause(); break;
                case "cancel": SttService.cancel(); break;
                case "stop": SttService.stop(); break;
            }
        } else if (_activeMode === "audio") {
            switch (action) {
                case "pause": AudioRecorderService.pause(); break;
                case "cancel": AudioRecorderService.cancel(); break;
                case "stop": AudioRecorderService.stop(); break;
            }
        }
    }

    // ── Auto-release on service deactivation ───────────────────────

    Connections {
        target: AudioRecorderService

        function onActiveChanged(): void {
            if (!AudioRecorderService.active)
                root.release("audio");
        }
    }

    Connections {
        target: SttService

        function onActiveChanged(): void {
            if (!SttService.active)
                root.release("stt");
        }
    }
}
