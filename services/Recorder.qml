pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import Symmetria

Singleton {
    id: root

    // Verification timing constants
    readonly property int shutdownVerifyDelay: 500  // pkill is fast, check quickly
    readonly property int maxStopRetries: 5

    readonly property alias running: props.running
    readonly property alias paused: props.paused
    readonly property alias elapsed: props.elapsed

    // Max time to wait for gpu-screen-recorder to appear during region selection.
    // User interaction with slurp can take a while, so we poll repeatedly.
    readonly property int regionPollInterval: 1000    // Check every 1 second
    readonly property int regionPollTimeout: 60000    // Give up after 60 seconds
    readonly property int fullscreenVerifyDelay: 1500 // Single check after 1.5s for fullscreen

    function start(extraArgs: list<string>): void {
        // Only start if not already running
        if (props.running) {
            console.log("[Recorder] start IGNORED — already recording");
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

        // Detect region mode: args contain "-r" or "-sr" (combined short flags)
        const isRegion = args.some(a => a === "-r" || a.includes("r"));

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

    property bool startPending: false
    property bool _regionMode: false
    property int _regionPollElapsed: 0

    property bool stopPending: false
    property int stopRetryCount: 0

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
            root._regionPollElapsed += interval;
            console.log("[Recorder] regionPoll tick —", root._regionPollElapsed, "ms elapsed");
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
                    props.running = false;
                } else {
                    console.log("[Recorder] regionPoll — recorder not found, checking slurp...");
                    slurpCheckProc.running = true;
                }
            } else {
                // Fullscreen mode: single check failed
                root.startPending = false;
                console.log("[Recorder] VERIFY FAILED — gpu-screen-recorder not running");
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
                    Toaster.toast(
                        qsTr("Stop failed"),
                        qsTr("Recording may need manual termination"),
                        "error",
                        Toast.Error
                    );
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
}
