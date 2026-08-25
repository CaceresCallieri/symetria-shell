pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import Symmetria

Singleton {
    id: root

    // Timing constants
    readonly property int shutdownVerifyDelay: 500  // pkill is fast, check quickly
    readonly property int maxStopRetries: 5
    readonly property int regionPollInterval: 1000    // Check every 1 second
    readonly property int regionPollTimeout: 60000    // Give up after 60 seconds
    readonly property int fullscreenVerifyDelay: 1500 // Single check after 1.5s for fullscreen

    readonly property alias running: props.running
    readonly property alias paused: props.paused
    readonly property alias elapsed: props.elapsed

    // Internal start-flow state
    property bool startPending: false
    property bool _regionMode: false
    property int _regionPollElapsed: 0

    // Internal stop-flow state
    property bool stopPending: false
    property int stopRetryCount: 0

    function start(extraArgs: list<string>): void {
        // Only start if not already running
        if (props.running) {
            console.log("[Recorder] start IGNORED — already recording");
            // Surface feedback for entry points without a disabled state (e.g. the
            // keychords recording menu). The dashboard Record card disables its
            // button while running, so it never reaches this branch.
            Toaster.toast(qsTr("Already recording"), qsTr("Stop the current recording from the dashboard first"), "screen_record", Toast.Info);
            return;
        }
        if (startPending) {
            console.log("[Recorder] start IGNORED — start in progress");
            return;
        }

        // Build command and fire-and-forget via execDetached.
        // We CANNOT use QML Process here because gpu-screen-recorder (launched by the CLI)
        // inherits the Process pipe FDs and keeps them open forever, blocking onExited.
        const baseCmd = ["symmetria", "record"];
        const args = Array.from(extraArgs).filter(s => s.length > 0);
        const cmd = baseCmd.concat(args);

        // Detect region mode: only "-r" and combined "-sr" are region flags (all
        // in-shell callers pass separate flags now, but external `symmetria shell`
        // invocations may still combine them). -w (active window) is intentionally
        // NOT region mode: the CLI resolves the geometry itself without slurp, so
        // the instant fullscreen-style verify applies, not region polling.
        const isRegion = args.some(a => a === "-r" || a === "-sr");

        console.log("[Recorder] start —", isRegion ? "REGION" : "FULLSCREEN", "— execDetached:", JSON.stringify(cmd));
        Quickshell.execDetached(cmd);
        startPending = true;
        _regionMode = isRegion;
        _regionPollElapsed = 0;

        if (isRegion) {
            // Region: CLI blocks on slurp, so poll repeatedly until recorder appears
            console.log("[Recorder] region mode — starting poll (every", regionPollInterval, "ms, timeout", regionPollTimeout, "ms)");
            regionPollTimer.start();
        } else {
            // Fullscreen: single check after delay
            verifyTimer.start();
        }
    }

    function stop(): void {
        if (!props.running) {
            console.log("[Recorder] stop IGNORED — not recording");
            return;
        }
        if (stopPending) {
            console.log("[Recorder] stop IGNORED — stop in progress");
            return;
        }
        console.log("[Recorder] initiating stop (with clipboard copy)");

        // Use execDetached because CLI blocks waiting for notification action.
        // Pass -c to copy the recording path to clipboard.
        Quickshell.execDetached(["symmetria", "record", "-c"]);

        stopPending = true;
        stopVerifyTimer.start();
    }

    function togglePause(): void {
        if (!props.running) {
            console.log("[Recorder] togglePause IGNORED — not recording");
            return;
        }
        console.log("[Recorder] toggling pause");

        // Use execDetached - pause is quick and doesn't need tracking
        Quickshell.execDetached(["symmetria", "record", "-p"]);

        // Toggle state immediately - pause/resume is synchronous via signal
        props.paused = !props.paused;
        console.log("[Recorder] paused =", props.paused);
    }

    Component.onCompleted: {
        console.log("[Recorder] service initialized, startPending:", startPending, "running:", props.running);
    }

    PersistentProperties {
        id: props

        property bool running: false
        property bool paused: false
        property real elapsed: 0 // Might get too large for int

        reloadableId: "recorder"
    }

    // Sync state on startup - check if gpu-screen-recorder is already running
    Process {
        id: startupCheck

        running: true  // Run once on startup
        command: ["pidof", "gpu-screen-recorder"]
        onExited: code => {
            const isRunning = code === 0;
            console.log("[Recorder] startup check — gpu-screen-recorder running:", isRunning);
            props.running = isRunning;
        }
    }

    // Fullscreen verify: single check after a delay
    Timer {
        id: verifyTimer
        interval: root.fullscreenVerifyDelay
        onTriggered: {
            console.log("[Recorder] verifyTimer fired — checking pidof");
            verifyProc.running = true;
        }
    }

    // Region verify: poll repeatedly while slurp blocks, then recorder starts
    Timer {
        id: regionPollTimer
        interval: root.regionPollInterval
        repeat: true
        onTriggered: {
            root._regionPollElapsed += root.regionPollInterval;
            console.log("[Recorder] regionPoll tick —", root._regionPollElapsed, "ms elapsed");
            // Skip this tick if the previous pidof check is still running
            if (!verifyProc.running)
                verifyProc.running = true;
        }
    }

    Process {
        id: verifyProc
        command: ["pidof", "gpu-screen-recorder"]
        onExited: code => {
            if (code === 0) {
                // gpu-screen-recorder is running — recording started!
                regionPollTimer.stop();
                root.startPending = false;
                console.log("[Recorder] VERIFIED — gpu-screen-recorder is running");
                props.running = true;
                props.paused = false;
                props.elapsed = 0;
            } else if (root._regionMode) {
                // Region mode: gpu-screen-recorder not found.
                // Check if slurp is still active (user still selecting).
                // If slurp is also gone → cancelled/failed, abort immediately.
                if (root._regionPollElapsed >= root.regionPollTimeout) {
                    regionPollTimer.stop();
                    root.startPending = false;
                    console.log("[Recorder] region poll TIMEOUT");
                    Toaster.toast(qsTr("Recording failed"), qsTr("Region recording timed out"), "error", Toast.Error);
                    props.running = false;
                } else if (!slurpCheckProc.running) {
                    console.log("[Recorder] regionPoll — recorder not found, checking slurp...");
                    slurpCheckProc.running = true;
                }
            } else {
                // Fullscreen/window mode: single check failed. Window mode has a
                // realistic failure cause (no active window to resolve), so surface
                // it — the region paths already toast on their failure branches.
                root.startPending = false;
                console.log("[Recorder] VERIFY FAILED — gpu-screen-recorder not running");
                Toaster.toast(qsTr("Recording failed"), qsTr("Recorder did not start"), "error", Toast.Error);
                props.running = false;
            }
        }
    }

    // Secondary check: is slurp still running? If not, the region operation is done.
    Process {
        id: slurpCheckProc
        command: ["pidof", "slurp"]
        onExited: code => {
            if (code === 0) {
                // slurp still running — user is still selecting, keep polling
                console.log("[Recorder] slurp still active — user selecting region");
            } else {
                // slurp exited AND gpu-screen-recorder not running → cancelled or failed
                regionPollTimer.stop();
                root.startPending = false;
                console.log("[Recorder] slurp exited, no recorder — recording cancelled or failed");
                props.running = false;
            }
        }
    }

    // Verify recording stopped after execDetached
    Timer {
        id: stopVerifyTimer
        interval: root.shutdownVerifyDelay
        onTriggered: stopVerifyProc.running = true
    }

    Process {
        id: stopVerifyProc
        command: ["pidof", "gpu-screen-recorder"]
        onExited: code => {
            if (code === 0) {
                // Still running - retry or give up
                root.stopRetryCount++;
                if (root.stopRetryCount >= root.maxStopRetries) {
                    console.error("[Recorder] stop verify FAILED after", root.maxStopRetries, "retries");
                    Toaster.toast(qsTr("Stop failed"), qsTr("Recording may need manual termination"), "error", Toast.Error);
                    root.stopPending = false;
                    root.stopRetryCount = 0;
                } else {
                    console.warn("[Recorder] stop verify — still running, retry", root.stopRetryCount);
                    stopVerifyTimer.start();
                }
            } else {
                // Stopped successfully
                console.log("[Recorder] recording stopped successfully");
                props.running = false;
                props.paused = false;
                root.stopPending = false;
                root.stopRetryCount = 0;
            }
        }
    }

    Connections {
        target: Time
        enabled: props.running && !props.paused

        function onSecondsChanged(): void {
            props.elapsed++;
        }
    }

    // IPC start surface for the keychords recording menu. Routing through this
    // service's start() — rather than invoking `symmetria record` directly — is
    // what keeps Recorder.running in sync: running-state is only updated by
    // start()/stop()'s verify polling and the startup pidof check, so a direct CLI
    // recording would run but never appear as "recording" in the bar/utility
    // dashboard. The Record card uses these same start([...]) variants.
    //
    // stop() is exposed for the keychords menu ("s" while recording) and the
    // Super+Alt+Space Hyprland bind — it is safe under rapid external invocation
    // because it no-ops unless running and guards re-entry via stopPending.
    // togglePause() is intentionally NOT exposed: it flips props.paused
    // optimistically with no in-progress guard and would desync under rapid
    // external invocation — add that guard before ever exposing it.
    //
    // Target is "screenRecorder", NOT "recorder" — "recorder" is already owned by
    // the audio/STT recorder (modules/recorder/RecorderRoot.qml).
    IpcHandler {
        target: "screenRecorder"

        function fullscreen(): void {
            root.start([]);
        }

        function region(): void {
            root.start(["-r"]);
        }

        // Active window: records the window's current screen region (resolved by
        // the CLI via `hyprctl activewindow`). Instant like fullscreen — no slurp —
        // so start()'s single-check verify path applies, not region polling.
        function window(): void {
            root.start(["-w"]);
        }

        function fullscreenAudio(): void {
            root.start(["-s"]);
        }

        function regionAudio(): void {
            root.start(["-r", "-s"]);
        }

        function windowAudio(): void {
            root.start(["-w", "-s"]);
        }

        function stop(): void {
            root.stop();
        }

        // Meeting mode: fullscreen + system audio + microphone merged into one
        // track (CLI: `record -s -m`). Captures BOTH sides of a video call — the
        // remote voice via default_output and the local voice via default_input.
        function meeting(): void {
            root.start(["-s", "-m"]);
        }
    }
}
