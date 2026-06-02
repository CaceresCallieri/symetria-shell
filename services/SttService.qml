pragma Singleton

import qs.config
import qs.services
import qs.utils
import Quickshell
import Quickshell.Io
import Symmetria
import QtQuick

/// Native speech-to-text service — single job at a time.
///
/// Only one SttJob may exist at any time. A new recording cannot start until the
/// current job completes (success animation finishes) or is cancelled.
///
/// Pipeline: pw-record → WAV file → curl (OpenAI API) → wl-copy [→ sendshortcut inject]
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

    /// Whether a job exists (controls drawer visibility)
    readonly property bool active: _job !== null

    /// The current job, or null. Read by recorder UI components.
    readonly property SttJob job: _job

    /// The currently recording job (at most one), or null
    readonly property SttJob activeRecording: _activeRecording

    /// Whether the delivery mode radio toggle should be shown (from config)
    readonly property bool isAskMode: _deliveryMode === "ask"


    /// Emitted when an action is successfully dispatched.
    /// Used by Content.qml to animate the corresponding control button.
    /// sessionId identifies the job; empty means service-level action.
    signal actionTriggered(string sessionId, string action)

    // ─────────────────────────────────────────────────────────────────────────
    // Shared state (service-level, not per-job)
    // ─────────────────────────────────────────────────────────────────────────

    property SttJob _job: null
    property SttJob _activeRecording: null

    // Old job kept alive across a restart so _job can swap atomically
    // oldJob → newJob without going through null. Destroyed from inside
    // _startInternal after the new job takes over.
    property SttJob _pendingOldJob: null

    // Toggle debouncing
    property real _lastToggleTime: 0
    readonly property int _toggleDebounceMs: 200

    // Runtime delivery choice for "ask" mode.
    // Persists across recordings within the same shell session.
    property string _lastDeliveryChoice: "submit"

    // Temp directory readiness
    property bool _tempDirReady: false

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
    // Persistent storage for audio/sidecars whose transcription failed.
    // Lives under XDG_STATE_HOME so it survives shell restart and logout
    // (unlike _tempDir, which is tmpfs). Created on startup below.
    readonly property string _recoveryDir: `${Paths.state}/stt/recoverable`
    // Persistent storage for *successful* recordings, retained as a safety net
    // against silent truncation / bad transcriptions (see SttConfig.cache).
    // Also on disk so the "keep for a day" window survives logout/reboot.
    // Pruned by age (Config.stt.cache.retainSuccessHours) and count.
    readonly property string _historyDir: `${Paths.state}/stt/history`

    // Delete retained successful-recording entries older than the configured
    // window. Called at startup (sweeps stale files from previous days even if
    // no new recording happens) and after each successful persist. Fire-and-
    // forget — a transient failure just defers cleanup to the next call.
    function _pruneHistory(): void {
        const hours = Config.stt?.cache?.retainSuccessHours ?? 24;
        if (hours <= 0) return;
        const mins = Math.round(hours * 60);
        Quickshell.execDetached(["find", _historyDir, "-maxdepth", "1",
            "-name", "session_*", "-mmin", `+${mins}`, "-delete"]);
    }

    // Delivery mode from config: "clipboard" (default), "inject", "submit", or "ask"
    readonly property string _deliveryMode: {
        const mode = Config.stt?.deliveryMode ?? "clipboard";
        if (mode === "inject" || mode === "submit" || mode === "ask") return mode;
        return "clipboard";
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Orchestrator commands
    // ─────────────────────────────────────────────────────────────────────────

    /// Toggle: start if idle, submit if recording, retry if errored.
    function toggle(): void {
        const now = Date.now();
        if (now - _lastToggleTime < _toggleDebounceMs) {
            console.log("[STT:D19] toggle() DEBOUNCED | elapsed:", now - _lastToggleTime, "ms");
            return;
        }
        Logger.log("qml", "stt", "toggle | activeRecording=" + (_activeRecording !== null) + " job=" + (_job !== null));
        _lastToggleTime = now;

        if (_activeRecording) {
            stop();
        } else if (!_job) {
            start();
        } else {
            // Job exists but not recording (processing/delivering) — check for error
            if (_job.state === "error" && _job.errorSource !== "config") {
                _job.retry();
                actionTriggered(_job.sessionId, "retry");
            } else {
                // Job is processing/delivering — inform the user
                Toaster.toast(
                    qsTr("STT is busy"),
                    qsTr("Wait for the current job to finish"),
                    "",
                    Toast.Warning
                );
            }
        }
    }

    /// Start a new recording job. Blocked if a job already exists.
    function start(): void {
        if (_job) {
            Toaster.toast(
                qsTr("STT is busy"),
                qsTr("Wait for the current job to finish"),
                "",
                Toast.Warning
            );
            return;
        }
        _startInternal();
    }

    /// Internal start — bypasses the single-job guard.
    /// Used by restartDelayTimer where the old job may still be animating out.
    function _startInternal(): void {
        if (_activeRecording) {
            console.warn("[STT] _startInternal() called while already recording — ignoring");
            return;
        }
        Logger.log("qml", "stt", "start | delivery=" + _deliveryMode);

        // Check API key before starting (SttJob._resolvedApiKey checks
        // both Config.stt.apiKey and OPENAI_API_KEY env var)
        const job = _createJob();
        if (job._resolvedApiKey === "") {
            job._setErrorState("config", "API key not configured",
                "Set OPENAI_API_KEY env var or stt.apiKey in shell.json", false);
            _job = job;
            return;
        }

        // Capture target window and resolve agent data synchronously.
        job._captureTargetWindow();
        job._resolveAgentTarget();
        Logger.log("qml", "stt", "session | id=" + job.sessionId + " target=" + job._targetWindowAddress + " class=" + job._targetWindowClass);

        _activeRecording = job;
        job._state = "recording";

        // Assign _job AFTER state is "recording" so the bar embed
        // (which binds to _activeJob via job) sees the correct state immediately.
        // When called from the restart path, _job transitions directly from
        // the parked old job to this new job — the bar embed's binding on
        // RecordingSessionManager.currentJob re-evaluates, swapping content
        // seamlessly without any close/open animation.
        _job = job;

        // If a restart is in progress, dispose the parked old job now that
        // the new job has taken over. Must happen AFTER _job = job so the
        // QML binding on currentJob has moved to the new reference before
        // the old one is destroyed.
        if (_pendingOldJob) {
            _pendingOldJob.destroy();
            _pendingOldJob = null;
        }

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

    /// Cancel the active recording (discard audio).
    function cancel(): void {
        // A restart is mid-flight if _pendingOldJob is set and the
        // restartDelayTimer hasn't fired _startInternal yet. In that window
        // _activeRecording is already null, so the normal branch below would
        // silently no-op — leaving the parked old job leaked and the bar
        // embed stuck on it. Abort the pending restart explicitly.
        if (_pendingOldJob) {
            restartDelayTimer.stop();
            const pending = _pendingOldJob;
            _pendingOldJob = null;
            actionTriggered(pending.sessionId, "cancel");
            // Run the normal close-animation path now that we know the user
            // didn't actually want to continue recording.
            _removeJob(pending);
            return;
        }

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
    ///
    /// Plays a close → open animation sequence:
    ///   T=0          close animation starts (closing=true on old job causes
    ///                Bar.qml's declarative _showEmbed binding to evaluate
    ///                false → implicitWidth animates to 0 → shrink)
    ///   T=500ms      _startInternal fires: _job swaps to new job atomically,
    ///                old job is destroyed, Bar.qml's _showEmbed re-evaluates
    ///                true (new job has closing=false) → open animation,
    ///                pw-record spawns, recording begins.
    ///
    /// The lock-release bug the old 500ms delay suffered from is prevented by
    /// parking the old job in _pendingOldJob so _job stays non-null across
    /// the animation window — SttService.active never flips false, so
    /// RecordingSessionManager doesn't auto-release the "stt" lock.
    function restart(): void {
        if (!_activeRecording) return;
        actionTriggered(_activeRecording.sessionId, "restart");
        restartDelayTimer.stop();
        const job = _activeRecording;
        _activeRecording = null;
        _sessionVocabHints = [];
        vocabHintsVisible = false;
        job.cancelForRestart();
        // Trigger the bar embed's close animation. job.closing=true causes the
        // declarative _showEmbed binding in Bar.qml to evaluate false, which
        // animates implicitWidth to 0 (shrink). _job is NOT cleared here —
        // _pendingOldJob keeps it alive so the lock stays held; the swap
        // happens in _startInternal.
        job.closing = true;

        // Defense-in-depth: clean up any leftover pending job that wasn't consumed
        // by _startInternal. Structurally unreachable via the normal code path
        // (restart() returns early when !_activeRecording, which is always the
        // case when _pendingOldJob is set), but retained as an explicit
        // leak-prevention guard in case future callers change the preconditions.
        if (_pendingOldJob && _pendingOldJob !== job) {
            _pendingOldJob._destroyCleanup();
            _pendingOldJob.destroy();
        }
        _pendingOldJob = job;

        restartDelayTimer.start();
    }

    /// Retry the most recent errored job.
    function retry(): void {
        if (!_job || _job.state !== "error" || _job.errorSource === "config") return;
        actionTriggered(_job.sessionId, "retry");
        _job.retry();
    }

    /// Switch the runtime delivery choice (only effective in "ask" mode).
    /// This is the IPC entry point — emits actionTriggered for UI feedback.
    /// For direct UI interaction, use SttJob.setDeliveryChoice (no signal).
    function setDeliveryChoice(mode: string): void {
        if (_deliveryMode !== "ask") {
            console.debug("[STT] setDeliveryChoice() ignored: deliveryMode is", _deliveryMode, "(not ask)");
            return;
        }
        if (mode !== "clipboard" && mode !== "inject" && mode !== "submit") return;
        if (_lastDeliveryChoice === mode) return;
        _lastDeliveryChoice = mode;
        if (_activeRecording) {
            _activeRecording._activeDeliveryChoice = mode;
            actionTriggered(_activeRecording.sessionId, "mode-" + mode);
        }
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
    // Job lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    Component { id: jobComponent; SttJob {} }

    function _createJob(): SttJob {
        const job = jobComponent.createObject(root, {
            sessionId: Date.now().toString(),
            _activeDeliveryChoice: _lastDeliveryChoice
        });

        job.finished.connect(() => _onJobFinished(job));
        job.readyForDelivery.connect(() => job._startDeliveryChain());

        // Caller must assign _job AFTER setting job state, so that
        // UI consumers binding to job see the correct state immediately.
        return job;
    }

    function _removeJob(job: SttJob): void {
        job.closing = true;  // closes embed via _showEmbed declarative binding in Bar.qml
        job.startRemoval();  // per-job timer, avoids overwrite race
    }

    function _onJobFinished(job: SttJob): void {
        // Job reported success and its successTimer fired — remove it
        _removeJob(job);
    }

    function _finalizeRemoval(job: SttJob): void {
        if (_job === job)
            _job = null;
        job.destroy();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Service-level timers & processes
    // ─────────────────────────────────────────────────────────────────────────

    // Delay between setting closing=true on the old job and swapping in the
    // new job. Matched to the bar embed's scale Behavior duration
    // (expressiveDefaultSpatial = 500ms) so the close (scale → 0) animation
    // has fully played out before the new job triggers the open (scale → 1)
    // animation. The lock isn't released during this window because
    // _pendingOldJob keeps _job non-null (see restart()).
    Timer {
        id: restartDelayTimer
        interval: Appearance.anim.durations.expressiveDefaultSpatial
        onTriggered: root._startInternal()
    }

    // Ensure temp directory exists before first recording
    Process {
        id: tempDirProcess
        command: ["mkdir", "-p", root._tempDir]
        onExited: (code, status) => {
            if (code !== 0) {
                console.error("[STT] Failed to create temp directory:", root._tempDir);
                if (root._activeRecording)
                    root._activeRecording._setErrorState("internal", "Failed to create temp directory", "Check permissions", false);
                return;
            }
            root._tempDirReady = true;
            if (root._activeRecording && root._activeRecording._state === "recording")
                root._activeRecording._startRecording();
        }
    }

    // Create the persistent recovery directory once at startup. Fire-and-forget:
    // jobs only attempt to write into it after a final error, and those writes
    // also `mkdir -p` defensively, so a transient failure here is non-fatal.
    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", root._recoveryDir]);
        Quickshell.execDetached(["mkdir", "-p", root._historyDir]);
        // Sweep retained successful recordings that have aged out since last run.
        root._pruneHistory();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Cleanup
    // ─────────────────────────────────────────────────────────────────────────

    Component.onDestruction: {
        restartDelayTimer.stop();
        if (_pendingOldJob)
            _pendingOldJob._destroyCleanup();
        // Guard: during the restart gap _job === _pendingOldJob, so skip the
        // second _destroyCleanup call — cancelForRestart() already tore everything
        // down, and calling _stopAllTimers() + process signals a second time is
        // harmless but noisy.
        if (_job && _job !== _pendingOldJob)
            _job._destroyCleanup();
    }
}
