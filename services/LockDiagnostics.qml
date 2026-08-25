pragma Singleton
pragma ComponentBehavior: Bound

import qs.utils
import Quickshell
import QtQuick

// Lock-screen lifecycle observability.
//
// WHY THIS EXISTS: Symmetria's lock screen is its own in-process WlSessionLock
// surface (modules/lock/), NOT an external locker like hyprlock. Its visible
// background is a live ScreencopyView of the screen; the surface itself is
// `color: "transparent"`. The known failure mode is "session-lock armed but
// undrawn" around suspend/resume — almost always with the qs process still
// ALIVE (no coredump in 6+ weeks), which means a blank ScreencopyView, not a
// crash. So the highest-value vantage point is in-process: qs survives the
// failure and can self-report exactly why the surface is blank.
//
// This singleton writes an append-only JSON-lines timeline to
//   ~/.local/state/symmetria/lock/lifecycle.jsonl
// and a frequently-rewritten liveness file
//   ~/.local/state/symmetria/lock/heartbeat
// that an EXTERNAL watchdog (independent of qs) tails to catch the cases this
// process cannot self-report (true qs death, or a wedged surface whose
// screencopy never recovers). See docs/hyprlock-crash-observability.md.
//
// CONTRACT: every public method is fire-and-forget and exception-guarded. A
// logging failure must NEVER block or break lock/unlock. All disk writes go
// through Quickshell.execDetached (never synchronous), base64-encoded to avoid
// shell-quoting hazards (same idiom as services/SttJob.qml).
Singleton {
    id: root

    readonly property string dir: `${Paths.state}/lock`
    readonly property string logPath: `${root.dir}/lifecycle.jsonl`
    readonly property string heartbeatPath: `${root.dir}/heartbeat`

    // Rotate the timeline once it crosses this size so a crash loop can't fill
    // the disk. One previous generation is kept as lifecycle.jsonl.1.
    readonly property int maxBytes: 1024 * 1024

    // Resume correlation: epoch-ms of the last logind PrepareForSleep=false
    // edge. 0 until the first resume this session. Every event emitted after a
    // resume carries `sinceResumeMs`, which is the field most likely to be the
    // smoking gun for suspend/resume-clustered failures.
    property double lastResumeMs: 0

    // Current locked state. SINGLE SOURCE OF TRUTH is WlSessionLock.locked,
    // mirrored here via noteLocked() so diagnostics can never drift from the
    // real lock state. Callers annotate WHY via willLock() just before flipping.
    property bool locked: false

    // Best-effort reason for the next lock transition (idle-timeout /
    // about-to-sleep / shortcut / ipc / logind-lock). Consumed + cleared by
    // noteLocked(). Empty → "unknown".
    property string pendingReason: ""

    // Per-screen ScreencopyView content state: { "<screen name>": <bool> }.
    // `screencopyHealthy` aggregates this so the watchdog can distinguish a
    // wedged-but-alive surface (locked && !healthy) from a clean lock.
    property var surfaces: ({})

    readonly property bool screencopyHealthy: {
        const keys = Object.keys(root.surfaces);
        if (keys.length === 0)
            return false;
        return keys.every(k => root.surfaces[k] === true);
    }

    function _isoNow(): string {
        return new Date().toISOString();
    }

    // Append one event object as a JSON line. `extra` is an optional plain
    // object merged into the event. Always tagged with ISO-8601 ts, the shell
    // pid, and (post-resume) sinceResumeMs.
    function log(type: string, extra: var): void {
        try {
            const ev = {
                ts: root._isoNow(),
                type,
                pid: Quickshell.processId
            };
            if (root.lastResumeMs > 0)
                ev.sinceResumeMs = Math.round(Date.now() - root.lastResumeMs);
            if (extra)
                for (const k in extra)
                    ev[k] = extra[k];

            const b64 = TextEncoding.base64(JSON.stringify(ev));
            // base64 alphabet (A-Za-z0-9+/=) contains no shell metacharacters,
            // so single-quoting the payload is safe. Append + newline.
            Quickshell.execDetached(["sh", "-c", `printf '%s' '${b64}' | base64 -d >> '${root.logPath}'; printf '\\n' >> '${root.logPath}'`]);
        } catch (e) {
            console.warn("[LockDiagnostics] log failed:", e);
        }
    }

    // --- Lifecycle hooks (called from the lock path) -----------------------

    // Annotate the reason for the next lock transition. Call immediately before
    // setting WlSessionLock.locked. Best-effort: if a transition arrives without
    // a fresh reason it is logged as "unknown".
    function willLock(reason: string): void {
        root.pendingReason = reason ?? "";
    }

    // Mirror the real WlSessionLock.locked property. Wired from Lock.qml's
    // onLockedChanged so this is always accurate regardless of which path
    // triggered the transition.
    function noteLocked(value: bool): void {
        try {
            if (value === root.locked)
                return;
            root.locked = value;
            if (!value)
                root.surfaces = ({}); // drop stale per-screen health on unlock
            root.log(value ? "lock_engaged" : "lock_released", {
                reason: root.pendingReason || "unknown"
            });
            root.pendingReason = "";
            root._writeHeartbeat();
        } catch (e) {
            console.warn("[LockDiagnostics] noteLocked failed:", e);
        }
    }

    function markAboutToSleep(): void {
        root.log("about_to_sleep", {
            lockedAtSleep: root.locked
        });
    }

    function markResume(): void {
        root.lastResumeMs = Date.now();
        root.log("resume", {
            stillLocked: root.locked,
            screencopyHealthy: root.screencopyHealthy
        });
    }

    function markIdleAction(action: var, idle: bool): void {
        root.log("idle_action", {
            action: typeof action === "string" ? action : JSON.stringify(action),
            edge: idle ? "idle" : "return"
        });
    }

    // --- Surface / ScreencopyView hooks (called from LockSurface) ----------

    function markSurfaceCreated(screenName: string): void {
        try {
            // Clone, not mutate-in-place: reassigning the same object reference
            // would NOT fire surfacesChanged, leaving screencopyHealthy stale.
            const s = Object.assign({}, root.surfaces);
            s[screenName] = false; // created but no frame yet
            root.surfaces = s;
            root.log("surface_created", {
                screen: screenName
            });
            root._writeHeartbeat();
        } catch (e) {
            console.warn("[LockDiagnostics] markSurfaceCreated failed:", e);
        }
    }

    function markSurfaceDestroyed(screenName: string): void {
        try {
            const s = Object.assign({}, root.surfaces);
            delete s[screenName];
            root.surfaces = s;
            root.log("surface_destroyed", {
                screen: screenName
            });
        } catch (e) {
            console.warn("[LockDiagnostics] markSurfaceDestroyed failed:", e);
        }
    }

    // hasContent flipped on a screen's background ScreencopyView. A frame that
    // never arrives (stays false while locked) is the blank-capture signature.
    function markScreencopy(screenName: string, hasContent: bool): void {
        try {
            const s = Object.assign({}, root.surfaces);
            s[screenName] = hasContent;
            root.surfaces = s;
            root.log("screencopy", {
                screen: screenName,
                hasContent
            });
            root._writeHeartbeat();
        } catch (e) {
            console.warn("[LockDiagnostics] markScreencopy failed:", e);
        }
    }

    // --- Heartbeat ---------------------------------------------------------

    // The watchdog's stuck-lock rule:
    //   locked == true AND (heartbeat mtime is stale  OR  screencopyHealthy == false sustained)
    // mtime staleness catches qs death / event-loop stall; screencopyHealthy
    // catches a wedged-but-alive surface. We rewrite the file on every state
    // change AND on a 2s timer while locked, so a frozen mtime is meaningful.
    function _writeHeartbeat(): void {
        try {
            const hb = {
                ts: root._isoNow(),
                pid: Quickshell.processId,
                locked: root.locked,
                screencopyHealthy: root.screencopyHealthy,
                surfaces: root.surfaces
            };
            const b64 = TextEncoding.base64(JSON.stringify(hb));
            Quickshell.execDetached(["sh", "-c", `printf '%s' '${b64}' | base64 -d > '${root.heartbeatPath}'`]);
        } catch (e) {
            console.warn("[LockDiagnostics] heartbeat failed:", e);
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.locked
        onTriggered: root._writeHeartbeat()
    }

    Component.onCompleted: {
        // Ensure the state dir exists and rotate an oversized timeline before
        // the first write. Idempotent; runs detached.
        Quickshell.execDetached(["sh", "-c", `mkdir -p '${root.dir}'; f='${root.logPath}'; if [ -f "$f" ] && [ "$(stat -c%s "$f" 2>/dev/null || echo 0)" -gt ${root.maxBytes} ]; then mv -f "$f" "$f.1"; fi`]);
        root.log("logger_init", {
            shellPid: Quickshell.processId
        });
        // Stamp a fresh locked:false heartbeat so any leftover locked:true file
        // from a previous crash can't trip the watchdog before the first lock.
        root._writeHeartbeat();
    }
}
