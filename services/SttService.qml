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

    /// Streaming dictation toggle (runtime). Initialized from Config.stt.mode,
    /// flipped by toggleStreaming() (Super+Alt+D). When true, recordings use the
    /// streaming helper for live partials; when false, batch. Read by SttJob and
    /// the bar's dictation-status icon. NOT readonly — toggleStreaming() writes
    /// it imperatively (a readonly binding would block the write; see
    /// docs/qml-pitfalls.md "readonly blocks ALL assignment").
    property bool streamingActive: Config.stt?.mode === "streaming"

    /// Emitted when an action is successfully dispatched.
    /// Used by Content.qml to animate the corresponding control button.
    /// sessionId identifies the job; empty means service-level action.
    signal actionTriggered(string sessionId, string action)

    // ─────────────────────────────────────────────────────────────────────────
    // Shared state (service-level, not per-job)
    // ─────────────────────────────────────────────────────────────────────────

    property SttJob _job: null
    property SttJob _activeRecording: null
    property SttJob _pendingMesuraJob: null
    property bool _applyingMesuraControl: false

    // Old job kept alive across a restart so _job can swap atomically
    // oldJob → newJob without going through null. Destroyed from inside
    // _startInternal after the new job takes over.
    property SttJob _pendingOldJob: null

    // Toggle debouncing
    property real _lastToggleTime: 0
    readonly property int _toggleDebounceMs: 200

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
        if (hours <= 0)
            return;
        const mins = Math.round(hours * 60);
        Quickshell.execDetached(["find", _historyDir, "-maxdepth", "1", "-name", "session_*", "-mmin", `+${mins}`, "-delete"]);
    }

    // "Ducked = mic is hot": duck the master sink while audio is actively
    // being captured. Covers start/resume (→true) and pause/submit/cancel/
    // restart/crash (→false): stop()/cancel()/restart() null _activeRecording
    // synchronously; pause and pw-record crash flip the job's state away from
    // "recording". Lives here, not in SttJob: cancel/restart destroy the job
    // while its state is still "recording", which would leak a duck.
    readonly property bool _micHot: _activeRecording !== null && _activeRecording.recording

    on_MicHotChanged: {
        if (_micHot) {
            if (Config.stt.ducking.enabled)
                AudioDucking.duck(Config.stt.ducking.volume);
        } else {
            // Unconditional: handles ducking.enabled flipping false mid-duck
            AudioDucking.restore();
        }
    }

    // Default delivery mode from config: "clipboard" (default), "inject", or
    // "submit". Seeds each new job's _activeDeliveryChoice; mode keys override
    // per-job only (one-shot).
    readonly property string _deliveryMode: {
        const mode = Config.stt?.deliveryMode ?? "clipboard";
        if (mode === "inject" || mode === "submit")
            return mode;
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
                retry();
            } else {
                // Job is processing/delivering — inform the user
                Toaster.toast(qsTr("STT is busy"), qsTr("Wait for the current job to finish"), "", Toast.Warning);
            }
        }
    }

    /// Toggle streaming dictation mode (Super+Alt+D). Flips streamingActive,
    /// which switches subsequent recordings between streaming (live partials)
    /// and batch, and drives the bar's dictation-status icon. Combined toggle
    /// for now — later this may split into "mode" vs "warm the model" controls.
    function toggleStreaming(): void {
        streamingActive = !streamingActive;
        Logger.log("qml", "stt", "toggleStreaming → " + (streamingActive ? "streaming" : "batch"));
    }

    /// Start a new recording job. Blocked if a job already exists.
    function start(): void {
        if (_job || _pendingMesuraJob) {
            Toaster.toast(qsTr("STT is busy"), qsTr("Wait for the current job to finish"), "", Toast.Warning);
            return;
        }
        _startInternal();
    }

    function mesuraReservationPending(sessionId: string): bool {
        return _pendingMesuraJob?.sessionId === sessionId;
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
        const restartingMesuraJob = _pendingOldJob?._mesuraIntegrated === true ? _pendingOldJob : null;
        const job = _createJob(restartingMesuraJob?.sessionId ?? "", restartingMesuraJob?.activeDeliveryChoice ?? _deliveryMode);
        if (job._resolvedApiKey === "") {
            job._setErrorState("config", "API key not configured", "Set OPENAI_API_KEY env var or stt.apiKey in shell.json", false);
            if (RecordingSessionManager.acquire("stt"))
                _job = job;
            else
                job.destroy();
            return;
        }

        if (restartingMesuraJob !== null) {
            job._mesuraIntegrated = true;
            job._mesuraPeerPid = restartingMesuraJob._mesuraPeerPid;
            job._mesuraTarget = restartingMesuraJob._mesuraTarget;
            job._mesuraProjectName = restartingMesuraJob._mesuraProjectName;
            job._targetWindowAddress = restartingMesuraJob._targetWindowAddress;
            job._targetWindowClass = restartingMesuraJob._targetWindowClass;
            job._targetWindowPid = restartingMesuraJob._targetWindowPid;
            _activatePreparedJob(job, "recording");
            return;
        }

        // Capture target window and resolve agent data synchronously.
        job._captureTargetWindow();
        job._resolveAgentTarget();
        Logger.log("qml", "stt", "session | id=" + job.sessionId + " target=" + job._targetWindowAddress + " class=" + job._targetWindowClass);

        if (job._isMesuraClass(job._targetWindowClass) && job._targetWindowPid > 0) {
            _pendingMesuraJob = job;
            // Start immediately under Shell ownership. The exact Mesura target
            // is already captured; failure downgrades only to manual clipboard,
            // so the keybind stays useful without risking wrong-chat delivery.
            _activatePreparedJob(job, "recording");
            if (_job !== job)
                return;
            // Activate before reserve(): an unavailable peer can reject the
            // reservation synchronously, and the failure handler must see the
            // live job to install the manual clipboard fallback.
            const reservationStarted = MesuraDictation.reserve(job._targetWindowPid, job.sessionId, "shell");
            if (!reservationStarted) {
                _failMesuraReservation(job.sessionId, "Mesura dictation is unavailable");
                return;
            }
            return;
        }

        _activatePreparedJob(job, "recording");
    }

    function _activatePreparedJob(job: SttJob, initialState: string): void {
        if (!RecordingSessionManager.acquire("stt")) {
            if (job._mesuraIntegrated)
                MesuraDictation.sendControl("cancel");
            if (_pendingMesuraJob === job) {
                MesuraDictation.cancelReservation(job.sessionId);
                _pendingMesuraJob = null;
            }
            job.destroy();
            return;
        }

        _activeRecording = job;
        job._state = initialState;

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
        if (initialState === "recording" && _tempDirReady) {
            job._startRecording();
        } else if (!_tempDirReady && (initialState === "recording" || initialState === "paused")) {
            tempDirProcess.running = true;
        }
    }

    function _prepareRecordingDirectory(): void {
        if (!_tempDirReady && !tempDirProcess.running)
            tempDirProcess.running = true;
    }

    function _failMesuraReservation(sessionId: string, detail: string): void {
        const pending = _pendingMesuraJob;
        if (pending === null || pending.sessionId !== sessionId)
            return;
        _pendingMesuraJob = null;
        if (_job === pending) {
            pending._manualClipboardFallback = true;
            pending.setDeliveryChoice("clipboard");
            if (pending.state === "transcribed")
                pending._beginDeliveryAfterTranscription();
        } else {
            pending.destroy();
        }
        Toaster.toast(qsTr("STT: Mesura unavailable"), qsTr("%1. Recording continues; paste the result manually.").arg(detail), "error", Toast.Error);
    }

    function _acceptMesuraSession(peerPid: int, session: var, pendingJob: SttJob): void {
        if (session.phase !== "recording" && session.phase !== "paused") {
            if (_pendingMesuraJob === pendingJob) {
                const terminalPhase = session.phase === "completed" || session.phase === "failed" || session.phase === "cancelled";
                if (!terminalPhase)
                    MesuraDictation.sendControlTo(peerPid, session, "cancel");
                _failMesuraReservation(pendingJob.sessionId, `Mesura returned unsupported phase: ${session.phase}`);
            } else {
                MesuraDictation.sendControlTo(peerPid, session, "cancel");
                pendingJob.destroy();
            }
            return;
        }
        const alreadyActive = _job === pendingJob;
        MesuraDictation.acceptSession(peerPid, session);
        pendingJob._mesuraIntegrated = true;
        pendingJob._mesuraPeerPid = peerPid;
        pendingJob._mesuraTarget = session.target;
        pendingJob._mesuraProjectName = session.projectName ?? "Mesura Code";
        if (!alreadyActive) {
            pendingJob._applyingMesuraSnapshot = true;
            pendingJob._activeDeliveryChoice = session.mode;
            pendingJob._applyingMesuraSnapshot = false;
        }
        _pendingMesuraJob = null;
        if (session.phase === "recording" || session.phase === "paused") {
            if (alreadyActive) {
                if (pendingJob.activeDeliveryChoice !== session.mode)
                    MesuraDictation.setMode(pendingJob.activeDeliveryChoice);
                if (pendingJob.state === "transcribed") {
                    pendingJob._beginDeliveryAfterTranscription();
                    return;
                }
                MesuraDictation.updateState(pendingJob);
                return;
            }
            _activatePreparedJob(pendingJob, session.phase);
            MesuraDictation.updateState(pendingJob);
            return;
        }
        if (!RecordingSessionManager.acquire("stt")) {
            MesuraDictation.sendControl("cancel");
            pendingJob.destroy();
            return;
        }
        _job = pendingJob;
        pendingJob._setErrorState("mesura", "The Shell cannot resume this dictation phase", "Start a new recording", true);
    }

    function _startExternalMesuraSession(peerPid: int, session: var): void {
        if (_job !== null || _activeRecording !== null || _pendingMesuraJob !== null) {
            MesuraDictation.sendControlTo(peerPid, session, "cancel");
            Toaster.toast(qsTr("STT is busy"), qsTr("Wait for the current job to finish"), "", Toast.Warning);
            return;
        }
        const job = _createJob(session.sessionId, session.mode);
        if (job._resolvedApiKey === "") {
            MesuraDictation.sendControlTo(peerPid, session, "cancel");
            job.destroy();
            Toaster.toast(qsTr("STT: API key not configured"), qsTr("Set OPENAI_API_KEY or stt.apiKey"), "error", Toast.Error);
            return;
        }
        job._targetWindowPid = peerPid;
        job._targetWindowClass = "mesura-code";
        _acceptMesuraSession(peerPid, session, job);
    }

    /// Stop the active recording and submit for transcription.
    function stop(): void {
        if (!_activeRecording)
            return;
        const mesuraControlId = _activeRecording._mesuraIntegrated && !_applyingMesuraControl ? MesuraDictation.sendControl("stop") : "";
        actionTriggered(_activeRecording.sessionId, "stop");
        // Snapshot session hints onto the job before clearing service-level state.
        // The recording→stop path is async (recordProcess.onExited calls
        // _startTranscription later), so _sessionVocabHints would be empty
        // by the time transcription starts without this snapshot.
        _activeRecording._snapshotVocabHints = _sessionVocabHints.slice();
        _activeRecording.stop();
        if (mesuraControlId !== "")
            MesuraDictation.acknowledgeAction("control", mesuraControlId);
        _activeRecording = null;
        _sessionVocabHints = [];
        vocabHintsVisible = false;
    }

    /// Toggle pause on the active recording.
    function pause(): void {
        if (!_activeRecording)
            return;
        if (_activeRecording._state === "recording") {
            const mesuraControlId = _activeRecording._mesuraIntegrated && !_applyingMesuraControl ? MesuraDictation.sendControl("pause") : "";
            actionTriggered(_activeRecording.sessionId, "pause");
            _activeRecording.pause();
            if (mesuraControlId !== "")
                MesuraDictation.acknowledgeAction("control", mesuraControlId);
        } else if (_activeRecording._state === "paused") {
            const mesuraControlId = _activeRecording._mesuraIntegrated && !_applyingMesuraControl ? MesuraDictation.sendControl("resume") : "";
            actionTriggered(_activeRecording.sessionId, "resume");
            _activeRecording.resume();
            if (mesuraControlId !== "")
                MesuraDictation.acknowledgeAction("control", mesuraControlId);
        }
    }

    /// Cancel the active recording (discard audio).
    function cancel(): void {
        if (_pendingMesuraJob) {
            const pendingReservation = _pendingMesuraJob;
            _pendingMesuraJob = null;
            MesuraDictation.cancelReservation(pendingReservation.sessionId);
            if (_activeRecording === pendingReservation)
                _activeRecording = null;
            _sessionVocabHints = [];
            vocabHintsVisible = false;
            if (_job === pendingReservation) {
                actionTriggered(pendingReservation.sessionId, "cancel");
                pendingReservation.cancel();
            } else {
                pendingReservation.destroy();
            }
            return;
        }
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

        // Cancel the live recording if one exists; otherwise dismiss a FAILED
        // job. The fallback to _job is gated to the error state on purpose:
        //   - It lets a keybind/IPC tear down the failed-state card. Once a job
        //     errors, _activeRecording is already null (cleared at stop()), so
        //     without this cancel() would silently no-op and the user stays
        //     stuck — the error card's triggerPress() only animates the ✗ button
        //     (visual feedback) and never invokes cancel() itself, so the
        //     teardown must happen here, mirroring how retry() calls
        //     _job.retry() directly.
        //   - It deliberately does NOT cover processing/delivering/transcribed.
        //     In those states a transcribe/clipboard/inject Process is still
        //     running, and the delivery handlers (clipboardProcess/injectProcess
        //     onExited) aren't guarded against a mid-flight teardown — they'd
        //     flip the job to "success" after it was removed. The error state is
        //     quiescent (every Process has already exited), so tearing down
        //     there is race-free. Stuck processing is handled by
        //     processingTimeoutTimer → error instead.
        const target = _activeRecording ?? (_job?.state === "error" ? _job : null);
        if (!target)
            return;
        const mesuraControlId = target._mesuraIntegrated && !_applyingMesuraControl ? MesuraDictation.sendControl("cancel") : "";
        if (target._mesuraIntegrated)
            target._closeMesuraToasts();
        actionTriggered(target.sessionId, "cancel");
        // target === _activeRecording only when a live recording exists; on the
        // error-dismissal path target is _job and _activeRecording is already null.
        if (_activeRecording) {
            _activeRecording = null;
            _sessionVocabHints = [];
            vocabHintsVisible = false;
        }
        target.cancel();
        if (mesuraControlId !== "")
            MesuraDictation.acknowledgeAction("control", mesuraControlId);
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
        if (!_activeRecording)
            return;
        if (_pendingMesuraJob === _activeRecording) {
            const pendingJob = _activeRecording;
            actionTriggered(pendingJob.sessionId, "restart");
            const replacement = _createJob(pendingJob.sessionId, pendingJob.activeDeliveryChoice);
            replacement._targetWindowAddress = pendingJob._targetWindowAddress;
            replacement._targetWindowClass = pendingJob._targetWindowClass;
            replacement._targetWindowPid = pendingJob._targetWindowPid;
            pendingJob.cancelForRestart(true);
            _activeRecording = null;
            _sessionVocabHints = [];
            vocabHintsVisible = false;
            _pendingMesuraJob = replacement;
            _activatePreparedJob(replacement, "recording");
            pendingJob.destroy();
            return;
        }
        const mesuraControlId = _activeRecording._mesuraIntegrated && !_applyingMesuraControl ? MesuraDictation.sendControl("restart") : "";
        actionTriggered(_activeRecording.sessionId, "restart");
        restartDelayTimer.stop();
        const job = _activeRecording;
        _activeRecording = null;
        _sessionVocabHints = [];
        vocabHintsVisible = false;
        job.cancelForRestart(true);
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
        if (mesuraControlId !== "")
            MesuraDictation.acknowledgeAction("control", mesuraControlId);
    }

    /// Retry the most recent errored job.
    function retry(): void {
        if (!_job || _job.state !== "error" || _job.errorSource === "config")
            return;
        const mesuraControlId = _job._mesuraIntegrated && !_applyingMesuraControl ? MesuraDictation.sendControl("retry") : "";
        actionTriggered(_job.sessionId, "retry");
        _job.retry();
        if (mesuraControlId !== "")
            MesuraDictation.acknowledgeAction("control", mesuraControlId);
    }

    /// Switch the current job's delivery choice (one-shot — the next job
    /// re-seeds from Config.stt.deliveryMode). Targets _job rather than
    /// _activeRecording so mode keys keep working during processing/
    /// delivering/error: the choice is read at delivery time.
    /// This is the IPC entry point — emits actionTriggered for UI feedback.
    /// For direct UI interaction, use SttJob.setDeliveryChoice (no signal).
    function setDeliveryChoice(mode: string): void {
        if (mode !== "clipboard" && mode !== "inject" && mode !== "submit")
            return;
        // No-job guard: the session-scoped Hyprland binds could be stale
        // after a shell crash (cleared on next startup), so ignore quietly.
        // Also ignore the parked closing job during the restart window —
        // it is about to be destroyed and the new job re-seeds from config.
        if (!_job || _job.closing) {
            console.debug("[STT] setDeliveryChoice() ignored: no active job");
            return;
        }
        if (_job._activeDeliveryChoice === mode)
            return;
        _job.setDeliveryChoice(mode);
        if (_job._activeDeliveryChoice !== mode)
            return;
        actionTriggered(_job.sessionId, "mode-" + mode);
    }

    function sendNow(): void {
        if (!_job || _job.state !== "grace")
            return;
        const mesuraControlId = _job._mesuraIntegrated && !_applyingMesuraControl ? MesuraDictation.sendControl("send-now") : "";
        _job.sendNow();
        if (mesuraControlId !== "")
            MesuraDictation.acknowledgeAction("control", mesuraControlId);
        actionTriggered(_job.sessionId, "send-now");
    }

    /// Add a per-session vocabulary hint (shown as chip in the widget).
    function addSessionHint(word: string): void {
        const trimmed = word.trim();
        if (trimmed === "")
            return;
        if (_sessionVocabHints.some(h => h.toLowerCase() === trimmed.toLowerCase()))
            return;
        _sessionVocabHints = [..._sessionVocabHints, trimmed];
    }

    /// Remove a per-session vocabulary hint by index.
    function removeSessionHint(index: int): void {
        _sessionVocabHints = _sessionVocabHints.filter((_, i) => i !== index);
    }

    /// Toggle the vocabulary hints widget (only during active recording).
    function toggleVocabHints(): void {
        if (!_activeRecording)
            return;
        vocabHintsVisible = !vocabHintsVisible;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Session-scoped Hyprland keybinds
    // ─────────────────────────────────────────────────────────────────────────
    // These Alt combos only make sense while an STT session exists, so they
    // are registered dynamically (hyprctl keyword bind) when a job appears
    // and removed when it goes away — outside a session the keys pass through
    // to applications. Alt+V (pasteTranscription) stays a static global bind
    // in the Hyprland config because it is useful when idle.
    //
    // The bind window is `active` (job exists), not just recording: the
    // delivery choice is read at delivery time, so mode keys must work during
    // processing, and restart/hints no-op harmlessly via their own guards.
    // restart() never flips `active` false (_pendingOldJob keeps _job alive),
    // so there is no unbind/rebind churn across the restart animation.

    // [key, stt IPC function] pairs. Kept in sync with the comment block in
    // ~/.dotfiles/.config/hypr/keybindings.conf (STT section).
    readonly property var _sessionBinds: [["X", "cancel"], ["R", "restart"], ["space", "pause"], ["S", "mode clipboard"]   // S = Save to clipboard (not submit — that's Return)
        , ["I", "mode inject"], ["Return", "mode submit"], ["W", "hints"]]

    onActiveChanged: active ? _registerSessionBinds() : _unregisterSessionBinds()

    function _unbindCmd(bind: var): string {
        return `keyword unbind ALT,${bind[0]}`;
    }

    function _ipcCommand(target: string): string {
        return `qs ipc --pid ${Quickshell.processId} call ${target}`;
    }

    function _registerSessionBinds(): void {
        // unbind-then-bind in one batch: idempotent. Hyprland allows duplicate
        // binds on the same combo (which would double-fire the IPC command),
        // so a leftover bind from a crashed shell must be cleared first.
        const ipcCommand = _ipcCommand("stt");
        const cmds = _sessionBinds.map(b => `${_unbindCmd(b)} ; keyword bind ALT,${b[0]},exec,${ipcCommand} ${b[1]}`);
        Quickshell.execDetached(["hyprctl", "--batch", cmds.join(" ; ")]);
    }

    function _unregisterSessionBinds(): void {
        const recorderIpcCommand = _ipcCommand("recorder");
        const commands = _sessionBinds.map(_unbindCmd);
        commands.push(`keyword bindd ALT,space,Pause/Resume recording,exec,${recorderIpcCommand} pause`);
        commands.push(`keyword bindd ALT,X,Cancel recording,exec,${recorderIpcCommand} cancel`);
        Quickshell.execDetached(["hyprctl", "--batch", commands.join(" ; ")]);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Job lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    Component {
        id: jobComponent
        SttJob {}
    }

    function _createJob(sessionIdOverride: string, deliveryMode: string): SttJob {
        const job = jobComponent.createObject(root, {
            sessionId: sessionIdOverride !== "" ? sessionIdOverride : Date.now().toString(),
            _activeDeliveryChoice: deliveryMode
        });

        job.finished.connect(() => _onJobFinished(job));
        job.readyForDelivery.connect(() => job._beginDeliveryAfterTranscription());

        // Caller must assign _job AFTER setting job state, so that
        // UI consumers binding to job see the correct state immediately.
        return job;
    }

    Connections {
        target: MesuraDictation

        function onReservationConfirmed(peerPid: int, session: var): void {
            const pending = root._pendingMesuraJob;
            if (pending !== null && pending.sessionId === session.sessionId)
                root._acceptMesuraSession(peerPid, session, pending);
        }

        function onReservationFailed(sessionId: string, detail: string): void {
            root._failMesuraReservation(sessionId, detail);
        }

        function onExternalSessionRequested(peerPid: int, session: var): void {
            root._startExternalMesuraSession(peerPid, session);
        }

        function onControlRequested(sessionId: string, commandId: string, action: string): void {
            if (root._job?.sessionId !== sessionId)
                return;
            let handled = false;
            root._applyingMesuraControl = true;
            if (action === "pause") {
                handled = root._activeRecording?._state === "paused";
                if (root._activeRecording?._state === "recording") {
                    root.pause();
                    handled = true;
                }
            } else if (action === "resume") {
                handled = root._activeRecording?._state === "recording";
                if (root._activeRecording?._state === "paused") {
                    root.pause();
                    handled = true;
                }
            } else if (action === "stop") {
                handled = root._job.state === "processing" || root._job.state === "grace" || root._job.state === "delivering" || root._job.state === "confirming";
                if (root._activeRecording !== null) {
                    root.stop();
                    handled = true;
                }
            } else if (action === "cancel") {
                handled = root._activeRecording !== null || root._job.state === "error";
                if (handled)
                    root.cancel();
            } else if (action === "restart") {
                handled = root._activeRecording !== null;
                if (handled)
                    root.restart();
            } else if (action === "retry") {
                handled = root._job.state === "processing" || root._job.state === "delivering" || root._job.state === "confirming";
                if (root._job.state === "error" && root._job.errorSource !== "config") {
                    root.retry();
                    handled = true;
                }
            } else if (action === "send-now") {
                handled = root._job.state === "delivering" || root._job.state === "confirming";
                if (root._job.state === "grace") {
                    root.sendNow();
                    handled = true;
                }
            } else if (action === "start") {
                handled = root._job.state !== "idle";
            }
            root._applyingMesuraControl = false;
            if (handled)
                MesuraDictation.acknowledgeAction("control", commandId);
        }

        function onVocabularyRequested(sessionId: string, commandId: string, action: string, word: string, index: int): void {
            if (root._job?.sessionId !== sessionId)
                return;
            let handled = false;
            if (action === "add" && word.trim() !== "") {
                root.addSessionHint(word);
                handled = root._sessionVocabHints.some(hint => hint.toLowerCase() === word.trim().toLowerCase());
            } else if (action === "remove" && index >= 0 && index < root._sessionVocabHints.length) {
                root.removeSessionHint(index);
                handled = true;
            } else if (action === "toggle" && root._activeRecording !== null) {
                root.toggleVocabHints();
                handled = true;
            }
            if (handled)
                MesuraDictation.acknowledgeAction("vocabulary", commandId);
        }

        function onReceiptReceived(peerPid: int, receipt: var): void {
            if (root._job?._mesuraPeerPid === peerPid)
                root._job._handleMesuraReceipt(receipt);
        }

        function onSessionChangedForPeer(peerPid: int, session: var): void {
            if (session === null || root._job?.sessionId !== session.sessionId || root._job._mesuraPeerPid !== peerPid)
                return;
            if (root._job.activeDeliveryChoice !== session.mode) {
                root._job._applyingMesuraSnapshot = true;
                root._job.setDeliveryChoice(session.mode);
                root._job._applyingMesuraSnapshot = false;
            }
        }

        function onPeerConnected(peerPid: int): void {
            if (root._job?._mesuraPeerPid !== peerPid || root._job._mesuraDeliveryCommandId === "")
                return;
            if (root._job.state === "delivering" || root._job.state === "confirming")
                root._job._sendMesuraDelivery();
        }

        function onPeerDisconnected(peerPid: int, detail: string): void {
            if (root._job?._mesuraPeerPid === peerPid)
                root._job.handleMesuraPeerDisconnected(detail);
        }
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

    // Adopt recordings orphaned in the tmpfs working dir by a previous shell
    // that died mid-session (crash, or SIGTERM during dictation).
    // SttJob._destroyCleanup deliberately preserves the working WAV for
    // non-terminal jobs; this sweep moves those files into the persistent
    // recovery dir — before a reboot can discard the tmpfs copy — writes a
    // minimal sidecar per session, and toasts so the user knows the audio
    // is recoverable. Runs once at startup, before any new job can write
    // into the temp dir.
    Process {
        id: orphanSweepProcess

        command: ["sh", "-c", 'mkdir -p "$RECOVERY_DIR"\n' + 'count=0\n' +
            // -mmin +1 age gate: a LIVE capture's WAV has an ever-fresh mtime
            // (pw-record flushes continuously), so a recording started inside
            // the startup window can never be swept out from under pw-record.
            // A crashed file's mtime froze at death and qualifies within a
            // minute. Filenames contain no whitespace (session_<digits>_...),
            // so the word-split loop over find output is safe.
            'for f in $(find "$TEMP_DIR" -maxdepth 1 -name "session_*.wav" -mmin +1 2>/dev/null); do\n' + '    base=$(basename "$f")\n' +
            // session id = digits between "session_" and the first "_" or "."
            // (working files: session_<id>_segment_<N>.wav and, when segments
            // were concatenated, session_<id>_combined.wav — all adopted)
            '    sid=${base#session_}; sid=${sid%%[_.]*}\n' + '    mv -n "$f" "$RECOVERY_DIR/$base"\n' +
            // mv -n exits 0 even when it skips a name collision; only count
            // and sidecar-annotate files that actually left the temp dir.
            '    [ -e "$f" ] && continue\n' + '    sidecar="$RECOVERY_DIR/session_${sid}.json"\n' + '    if [ ! -e "$sidecar" ]; then\n' + '        printf \'{\\n  "sessionId": "%s",\\n  "recoveredAt": "%s",\\n  "reason": "orphaned recording adopted at shell startup",\\n  "audioFile": "%s"\\n}\\n\' "$sid" "$(date -Is)" "$base" > "$sidecar"\n' + '    fi\n' + '    count=$((count+1))\n' + 'done\n' + 'echo "$count"\n']
        onExited: (code, status) => {
            if (code !== 0)
                Logger.log("qml", "stt", "orphan-sweep-failed | code=" + code);
        }
        environment: ({
                TEMP_DIR: root._tempDir,
                RECOVERY_DIR: root._recoveryDir
            })
        stdout: StdioCollector {
            onStreamFinished: {
                const count = parseInt(text.trim(), 10) || 0;
                if (count === 0)
                    return;
                Logger.log("qml", "stt", "orphan-sweep | adopted=" + count);
                Toaster.toast(qsTr("STT: Recovered interrupted audio"), qsTr("%1 file(s) from a previous session moved to %2").arg(count).arg(root._recoveryDir), "", Toast.Warning);
            }
        }
    }

    // Create the persistent recovery directory once at startup. Fire-and-forget:
    // jobs only attempt to write into it after a final error, and those writes
    // also `mkdir -p` defensively, so a transient failure here is non-fatal.
    Component.onCompleted: {
        // Clear session keybinds left registered by a crashed shell — no job
        // exists at startup, so none of them should be bound.
        root._unregisterSessionBinds();
        Quickshell.execDetached(["mkdir", "-p", root._recoveryDir]);
        Quickshell.execDetached(["mkdir", "-p", root._historyDir]);
        // Sweep retained successful recordings that have aged out since last run.
        root._pruneHistory();
        // Rescue any recording the previous shell instance left behind.
        orphanSweepProcess.running = true;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Cleanup
    // ─────────────────────────────────────────────────────────────────────────

    Component.onDestruction: {
        _unregisterSessionBinds();
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
