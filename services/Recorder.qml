pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import Symmetria

Singleton {
    id: root

    readonly property alias running: props.running
    readonly property alias paused: props.paused
    readonly property alias elapsed: props.elapsed

    function start(extraArgs: list<string>): void {
        // Only start if not already running
        if (props.running) {
            console.log("Recorder: start ignored - already recording");
            return;
        }
        if (startPending) {
            console.log("Recorder: start ignored - start in progress");
            return;
        }

        // Build command and filter out any empty strings (QML spread quirk)
        const baseCmd = ["symmetria", "record"];
        const fullCmd = baseCmd.concat(Array.from(extraArgs));
        const cmd = fullCmd.filter(s => s.length > 0);
        console.log("Recorder: starting with command:", JSON.stringify(cmd));

        // Use execDetached so gpu-screen-recorder survives as a daemon
        Quickshell.execDetached(cmd);

        // Verify recording started after a brief delay
        startPending = true;
        verifyTimer.start();
    }

    property bool startPending: false

    property bool stopPending: false

    function stop(): void {
        // Only stop if currently running
        if (!props.running) {
            console.log("Recorder: stop ignored - not recording");
            return;
        }
        if (stopPending) {
            console.log("Recorder: stop ignored - stop in progress");
            return;
        }
        console.log("Recorder: initiating stop");

        // Use execDetached because CLI blocks waiting for notification action
        Quickshell.execDetached(["symmetria", "record"]);

        stopPending = true;
        stopVerifyTimer.start();
    }

    function togglePause(): void {
        if (!props.running) {
            console.log("Recorder: togglePause ignored - not recording");
            return;
        }
        console.log("Recorder: toggling pause");

        // Use execDetached - pause is quick and doesn't need tracking
        Quickshell.execDetached(["symmetria", "record", "-p"]);

        // Toggle state immediately - pause/resume is synchronous via signal
        props.paused = !props.paused;
        console.log("Recorder: paused =", props.paused);
    }

    Component.onCompleted: {
        console.log("Recorder: service initialized");
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
            console.log("Recorder: startup check - gpu-screen-recorder running:", isRunning);
            props.running = isRunning;
        }
    }

    // Verify recording actually started after execDetached
    Timer {
        id: verifyTimer
        interval: 1000  // Give gpu-screen-recorder time to initialize
        onTriggered: verifyProc.running = true
    }

    Process {
        id: verifyProc
        command: ["pidof", "gpu-screen-recorder"]
        onExited: code => {
            root.startPending = false;
            if (code === 0) {
                console.log("Recorder: recording verified - started successfully");
                props.running = true;
                props.paused = false;
                props.elapsed = 0;
            } else {
                console.error("Recorder: recording failed to start (gpu-screen-recorder not running)");
                Toaster.toast(qsTr("Recording failed"), qsTr("gpu-screen-recorder failed to start"), "error", Toast.Error);
                props.running = false;
            }
        }
    }

    // Verify recording stopped after execDetached
    Timer {
        id: stopVerifyTimer
        interval: 500  // Check quickly since pkill is fast
        onTriggered: stopVerifyProc.running = true
    }

    Process {
        id: stopVerifyProc
        command: ["pidof", "gpu-screen-recorder"]
        onExited: code => {
            root.stopPending = false;
            if (code === 0) {
                // Still running - try again or warn
                console.warn("Recorder: stop verify - still running, retrying...");
                stopVerifyTimer.start();
            } else {
                console.log("Recorder: recording stopped successfully");
                props.running = false;
                props.paused = false;
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
