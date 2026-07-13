pragma Singleton

import qs.services
import qs.config
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Duration presets shown by the dashboard card; kept here so UI and IPC
    // agree on the same list.
    readonly property list<int> presetMinutes: [15, 30, 45, 60, 90]

    property alias durationMinutes: props.durationMinutes

    readonly property bool running: props.deadlineMs > 0
    readonly property date deadline: new Date(props.deadlineMs)

    // Recomputed on every SystemClock second-tick via Time.date — no
    // dedicated Timer needed.
    readonly property int remainingSeconds: running ? Math.max(0, Math.ceil((props.deadlineMs - Time.date.getTime()) / 1000)) : 0

    readonly property string remainingText: {
        const h = Math.floor(remainingSeconds / 3600);
        const m = Math.floor((remainingSeconds % 3600) / 60);
        const s = remainingSeconds % 60;
        const pad = n => n.toString().padStart(2, "0");
        return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
    }

    // A deadline that passed longer ago than this is stale (e.g. it elapsed
    // while the machine was already asleep, or across a shell reload) and is
    // discarded instead of suspending on top of a fresh resume.
    readonly property int staleGraceMs: 15000

    onRemainingSecondsChanged: {
        if (running && remainingSeconds <= 0)
            _expire();
    }

    // A stale persisted deadline restores as remainingSeconds 0 → 0, which
    // never emits the change signal above, so also check once on startup.
    Component.onCompleted: {
        if (running && remainingSeconds <= 0)
            _expire();
    }

    function start(minutes: int): void {
        if (minutes > 0)
            props.durationMinutes = minutes;
        props.deadlineMs = Time.date.getTime() + props.durationMinutes * 60000;
    }

    function cancel(): void {
        props.deadlineMs = 0;
    }

    function toggle(): void {
        if (running)
            cancel();
        else
            start(0);
    }

    function _expire(): void {
        const overshootMs = Time.date.getTime() - props.deadlineMs;
        // Clear BEFORE dispatching: on resume the timer must read as idle,
        // otherwise the persisted deadline would immediately re-suspend.
        props.deadlineMs = 0;
        if (overshootMs <= root.staleGraceMs)
            Quickshell.execDetached(Config.session.commands.suspend);
    }

    PersistentProperties {
        id: props

        property int durationMinutes: 30
        property real deadlineMs: 0

        reloadableId: "suspendTimer"
    }

    IpcHandler {
        target: "suspendTimer"

        function isRunning(): bool {
            return root.running;
        }

        function remaining(): string {
            return root.running ? root.remainingText : "";
        }

        // minutes <= 0 uses the last-selected duration.
        function start(minutes: int): void {
            root.start(minutes);
        }

        function cancel(): void {
            root.cancel();
        }

        function toggle(): void {
            root.toggle();
        }
    }
}
