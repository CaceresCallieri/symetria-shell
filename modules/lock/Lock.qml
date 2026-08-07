pragma ComponentBehavior: Bound

import qs.components.misc
import qs.config
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Scope {
    property alias lock: lock

    WlSessionLock {
        id: lock

        signal unlock

        // Single source of truth for diagnostics' locked state (see
        // services/LockDiagnostics.qml). Mirroring the real property here means
        // every lock path — idle, logind, shortcut, IPC — is captured uniformly.
        onLockedChanged: LockDiagnostics.noteLocked(locked)

        onUnlock: unlockFailsafe.restart()

        LockSurface {
            lock: lock
            pam: pam
        }
    }

    // Failsafe for the unlock teardown.
    //
    // `locked = false` is normally set by the last step of LockSurface's
    // unlock animation, which is fine when that animation completes. It is
    // NOT guaranteed to: the surface can be destroyed mid-animation (output
    // removed/re-added across suspend/resume — the window LockDiagnostics
    // was built to investigate), and the animation driver may not advance
    // while no output is producing frames. Either case would strand an
    // ALREADY-AUTHENTICATED session locked forever.
    //
    // This timer outlives any single surface, which is the whole point — a
    // per-surface timer dies exactly when the case it guards against occurs.
    // It cannot weaken security: `unlock` is only emitted after PAM has
    // already succeeded, so the worst it can do is release a session the user
    // has already unlocked. When the animation wins the race, setting
    // `locked = false` twice is a no-op.
    //
    // PLACEMENT IS LOAD-BEARING — do NOT move this back inside WlSessionLock.
    // WlSessionLock's default property is `surface`, of type QQmlComponent, so
    // ANY child declared inside it is silently wrapped in an implicit
    // Component: a template, never an instance. The timer then never runs, and
    // its id is invisible to the enclosing file — `onUnlock` above failed with
    // "ReferenceError: unlockFailsafe is not defined" on every single unlock
    // for as long as it lived there. Scope's default property takes arbitrary
    // children, so here it is a real object.
    Timer {
        id: unlockFailsafe

        interval: Config.lock.beams.revealDuration + 2000
        onTriggered: {
            if (!lock.locked)
                return;
            LockDiagnostics.log("unlock_forced", {
                reason: "animation_did_not_complete"
            });
            lock.locked = false;
        }
    }

    Pam {
        id: pam

        lock: lock
    }

    CustomShortcut {
        name: "lock"
        description: "Lock the current session"
        onPressed: {
            LockDiagnostics.willLock("shortcut");
            lock.locked = true;
        }
    }

    CustomShortcut {
        name: "unlock"
        description: "Unlock the current session"
        onPressed: {
            LockDiagnostics.log("unlock_requested", {
                source: "shortcut"
            });
            lock.unlock();
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): void {
            LockDiagnostics.willLock("ipc");
            lock.locked = true;
        }

        function unlock(): void {
            LockDiagnostics.log("unlock_requested", {
                source: "ipc"
            });
            lock.unlock();
        }

        function isLocked(): bool {
            return lock.locked;
        }
    }
}
