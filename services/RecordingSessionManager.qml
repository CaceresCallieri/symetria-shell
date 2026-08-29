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

    /// Mesura owns only the presentation lease. The Shell still owns the job,
    /// recording lock, and controls while its widget is hidden.
    readonly property bool shellOwnsSttPresentation: !(SttService.job?._mesuraIntegrated === true && MesuraDictation.session?.sessionId === SttService.job?.sessionId && MesuraDictation.session?.presentation?.mesuraOwnsPresentation === true)

    // ── Internal state ─────────────────────────────────────────────

    property string _activeMode: ""

    readonly property var _modeNames: ({
            "stt": qsTr("Speech-to-Text"),
            "audio": qsTr("Audio Recorder")
        })

    /// Shared icon names for STT delivery modes. Used by Content.qml and RecordingBarEmbed.qml.
    // intentional var: JS string→string map (no QML typed map)
    readonly property var deliveryModeIcons: ({
            "clipboard": "content_copy",
            "inject": "input",
            "submit": "send"
        })

    /// The current recording job (from whichever service is active), or null.
    /// Centralizes mode→service→job resolution so consumers don't duplicate it.
    // intentional var: polymorphic (SttJob | AudioRecorderJob | null)
    readonly property var currentJob: {
        if (_activeMode === "stt")
            return shellOwnsSttPresentation ? SttService.job : null;
        if (_activeMode === "audio")
            return AudioRecorderService.job;
        return null;
    }

    /// Ordered delivery mode list for cycling (STT sessions).
    // intentional var: JS string array used as constant lookup table
    readonly property var _deliveryModes: ["clipboard", "inject", "submit"]

    /// Format seconds as MM:SS for elapsed time display.
    function formatElapsedTime(seconds: real): string {
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return mins.toString().padStart(2, '0') + ':' + secs.toString().padStart(2, '0');
    }

    /// Cycle the current job's delivery mode through clipboard → inject → submit.
    /// One-shot override: applies to the current STT job only; the next job
    /// re-seeds from Config.stt.deliveryMode.
    function cycleDeliveryMode(): void {
        const job = currentJob;
        if (!job || _activeMode !== "stt")
            return;
        const idx = _deliveryModes.indexOf(job.activeDeliveryChoice ?? "clipboard");
        SttService.setDeliveryChoice(_deliveryModes[(idx + 1) % _deliveryModes.length]);
    }

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
        Toaster.toast(qsTr("%1 is active").arg(activeName), qsTr("Cancel it before starting %1").arg(requestedName), "block", Toast.Warning);
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
            case "pause":
                SttService.pause();
                break;
            case "cancel":
                SttService.cancel();
                break;
            case "stop":
                SttService.stop();
                break;
            }
        } else if (_activeMode === "audio") {
            switch (action) {
            case "pause":
                AudioRecorderService.pause();
                break;
            case "cancel":
                AudioRecorderService.cancel();
                break;
            case "stop":
                AudioRecorderService.stop();
                break;
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
