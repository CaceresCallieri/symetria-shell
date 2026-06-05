pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io

// Virtual "Silent" power mode.
//
// power-profiles-daemon (PPD) only supports three profiles — power-saver,
// balanced, performance — and cannot be extended with a fourth. "Silent" is
// therefore modeled as a VIRTUAL mode: PPD pinned to power-saver PLUS a
// kernel-level overlay (CPU max-freq cap + boost off) applied by the root
// helper /usr/local/bin/quiet-mode. This singleton exposes the overlay's
// on/off state and toggles it through passwordless sudo.
//
// The overlay's source of truth is /etc/quiet-mode.state (ENABLED=0/1,
// CAP_MHZ), owned and written by the script. We watch that file so `enabled`
// tracks out-of-band changes too — the boot systemd service, the resume
// sleep-hook, or a manual `quiet-mode` CLI invocation — not just our own
// enable()/disable() calls.
Singleton {
    id: root

    // True when the kernel overlay is active. Derived from the state file rather
    // than a local toggle so it stays correct regardless of who flipped it.
    readonly property bool enabled: false

    function enable(): void {
        // -n: never prompt for a password. Relies on the NOPASSWD sudoers rule
        // (/etc/sudoers.d/quiet-mode); without it this fails fast, never hangs.
        toggleProc.exec(["sudo", "-n", "/usr/local/bin/quiet-mode", "on"]);
    }

    function disable(): void {
        toggleProc.exec(["sudo", "-n", "/usr/local/bin/quiet-mode", "off"]);
    }

    FileView {
        id: stateView

        path: "/etc/quiet-mode.state"
        watchChanges: true
        onFileChanged: reload()
        // State file is a shell-sourced KEY=VALUE list; match the ENABLED line only.
        onLoaded: root.enabled = /^ENABLED=1\b/m.test(text())
        onLoadFailed: root.enabled = false
    }

    Process {
        id: toggleProc

        // The script rewrites the state file on exit; FileView's inotify watch
        // will catch it, but reload explicitly so `enabled` flips promptly.
        onExited: stateView.reload()
    }
}
