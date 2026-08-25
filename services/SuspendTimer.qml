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
    // Only meaningful while running; reads as the Unix epoch (1970) when idle.
    readonly property date deadline: new Date(props.deadlineMs)

    // Recomputed on every SystemClock second-tick via Time.date — no
    // dedicated Timer needed. The schedule is absolute wall-clock time, so a
    // system clock jump (NTP correction, manual change) shifts the deadline;
    // a monotonic clock is intentionally NOT used so the persisted deadline
    // survives a shell reload.
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

    // Live-process resume: the machine slept with a deadline still armed,
    // running stayed true across the sleep, and Time.date jumps past the
    // deadline on wake — driving remainingSeconds to 0.
    onRemainingSecondsChanged: Qt.callLater(root._expire)

    // Reload/restore with an already-stale deadline: PersistentProperties
    // repopulates deadlineMs after construction, flipping running false→true
    // with remainingSeconds already 0 — so onRemainingSecondsChanged never
    // fires (0→0). Keying off running makes this guard order-independent of
    // when the restore lands, which a one-shot Component.onCompleted is not
    // (restore may complete after onCompleted has already run).
    onRunningChanged: Qt.callLater(root._expire)

    // REGRESSION GUARD — both handlers above used to call _expire() directly,
    // gated on `running && remainingSeconds <= 0`. Both halves of that were
    // wrong. The gate read `remainingSeconds` before its binding had been
    // re-evaluated, so arming the timer looked like an expiry and suspended the
    // machine the instant the card was toggled on; and _expire()'s write to
    // deadlineMs re-entered the `running` binding it was firing from, which Qt
    // aborts as a binding loop ("Binding loop detected for property running"),
    // freezing `running` true against a cleared deadline — armed at 0:00
    // forever, impossible to re-arm. Hence: no gate at all (_expire() derives
    // the verdict from raw state) and Qt.callLater to keep the write out of the
    // binding pass. Qt.callLater collapses the per-second repeat calls only
    // because `_expire` is a stable named method — an arrow function or closure
    // built at the call site is a fresh object every time and would NOT
    // coalesce. Full write-up: docs/qml-pitfalls.md § "A derived property reads
    // STALE inside a change handler that fires upstream of it".

    function start(minutes: int): void {
        if (minutes > 0)
            props.durationMinutes = minutes;
        // Clamp: durationMinutes is a writable public alias, and a non-positive
        // value would arm a deadline that fires instantly (immediate suspend).
        const mins = props.durationMinutes > 0 ? props.durationMinutes : 30;
        props.deadlineMs = Time.date.getTime() + mins * 60000;
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
        // Authoritative expiry test, from raw state only. The handlers above
        // fire unconditionally, so rejecting spurious triggers is this
        // function's job — see the regression guard for why no caller may
        // pre-filter on the derived remainingSeconds.
        if (props.deadlineMs <= 0)
            return;
        const overshootMs = Time.date.getTime() - props.deadlineMs;
        // `< 0`, never `<= 0`: deadlineMs is derived from the same
        // second-precision Time.date that drives the tick, so the on-time
        // expiry lands exactly on overshootMs === 0 and MUST pass through.
        if (overshootMs < 0)
            return; // deadline still ahead — spurious trigger, stay armed
        // Clear BEFORE dispatching: on resume the timer must read as idle,
        // otherwise the persisted deadline would immediately re-suspend.
        props.deadlineMs = 0;
        if (overshootMs > root.staleGraceMs) {
            console.log(`[SuspendTimer] discarding stale deadline — overshoot ${overshootMs}ms > ${root.staleGraceMs}ms grace`);
            return;
        }
        // Guard an empty override: session.commands.suspend is user-editable
        // via shell.json, and execDetached([]) would silently no-op after the
        // deadline is already cleared.
        const cmd = Config.session.commands.suspend;
        if (cmd && cmd.length > 0)
            Quickshell.execDetached(cmd);
        else
            console.warn("[SuspendTimer] session.commands.suspend is empty — deadline cleared, nothing dispatched");
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
