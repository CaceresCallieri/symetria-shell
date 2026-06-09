pragma ComponentBehavior: Bound

import "lock"
import qs.config
import qs.services
import Symmetria.Internal
import Quickshell
import Quickshell.Wayland

Scope {
    id: root

    required property Lock lock
    readonly property bool enabled: !Config.general.idle.inhibitWhenAudio || !Players.list.some(p => p.isPlaying)

    function handleIdleAction(action: var, idle: bool): void {
        if (!action)
            return;

        LockDiagnostics.markIdleAction(action, idle);

        if (action === "lock") {
            LockDiagnostics.willLock("idle-timeout");
            lock.lock.locked = true;
        } else if (action === "unlock")
            lock.lock.locked = false;
        else if (typeof action === "string")
            Hypr.dispatch(action);
        else
            Quickshell.execDetached(action);
    }

    LogindManager {
        onAboutToSleep: {
            LockDiagnostics.markAboutToSleep();
            if (Config.general.idle.lockBeforeSleep) {
                LockDiagnostics.willLock("about-to-sleep");
                root.lock.lock.locked = true;
            }
        }
        // The PrepareForSleep=false edge — previously unobserved. This is the
        // authoritative resume timestamp that anchors every subsequent event's
        // sinceResumeMs (the field most likely to expose suspend/resume-clustered
        // lock failures).
        onResumed: LockDiagnostics.markResume()
        onLockRequested: {
            LockDiagnostics.willLock("logind-lock");
            root.lock.lock.locked = true;
        }
        onUnlockRequested: root.lock.lock.unlock()
    }

    Variants {
        model: Config.general.idle.timeouts

        IdleMonitor {
            required property var modelData

            enabled: root.enabled && (modelData.enabled ?? true)
            timeout: modelData.timeout
            respectInhibitors: modelData.respectInhibitors ?? true
            onIsIdleChanged: root.handleIdleAction(isIdle ? modelData.idleAction : modelData.returnAction, isIdle)
        }
    }
}
