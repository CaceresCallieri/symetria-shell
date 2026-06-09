pragma ComponentBehavior: Bound

import qs.components.misc
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    property alias lock: lock

    WlSessionLock {
        id: lock

        signal unlock

        // Single source of truth for diagnostics' locked state (see
        // services/LockDiagnostics.qml). Mirroring the real property here means
        // every lock path — idle, logind, shortcut, IPC — is captured uniformly.
        onLockedChanged: LockDiagnostics.noteLocked(locked)

        LockSurface {
            lock: lock
            pam: pam
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
