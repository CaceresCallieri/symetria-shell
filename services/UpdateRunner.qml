pragma Singleton

import qs.config
import qs.services
import qs.utils
import Quickshell
import Quickshell.Io
import QtQuick

// Executor for the in-shell system update. Distinct from Updates.qml, which only
// COUNTS available updates — this RUNS the upgrade and exposes live progress that
// the bar updates popout renders in place (no separate window/overlay).
//
// Runs scripts/symmetria-update.sh as a single process (one sudo prompt via the
// keep-alive design inside the script). Parses two things off stdout:
//   * control markers  "::phase:<x>" / "::error:<msg>"  emitted by the script
//   * pacman's native  "(N/M) upgrading <pkg>"          for the live countdown
//
// The run is independent of the popout's hover state — start it, move away, and it
// keeps going; hovering again shows whatever phase it's currently in.
Singleton {
    id: root

    // Absolute path so the process works regardless of inherited CWD/env.
    readonly property string _script: `${Paths.home}/.dotfiles/scripts/symmetria-update.sh`

    readonly property bool running: proc.running

    // "idle" | "password" | "authenticating" | "syncing" | "building" | "installing" | "done" | "error"
    // "password": the process is running but blocked waiting for the password we feed
    // to its stdin (the popout shows a password field for this phase).
    property string phase: "idle"
    property int totalPackages: 0     // M from pacman's "(N/M)" — 0 until install begins
    property int installedCount: 0    // N from pacman's "(N/M)"
    property string currentPackage: ""
    property string errorMessage: ""

    // Curated tail of the live log (last N non-control lines), shown in the popout.
    property string logTail: ""
    property var _lines: []
    readonly property int _maxTail: 26
    readonly property int _maxBuffer: 400

    // True once a run finished and we want the popout to briefly show its terminal
    // state ("All updated" / error) before reverting to the plain counts view.
    readonly property bool finished: phase === "done" || phase === "error"

    // Remaining updates for the countdown. Before the install phase we mirror the
    // poller's count; during install we compute it live; at completion it's 0.
    readonly property int remaining: {
        if (phase === "done")
            return 0;
        if (totalPackages > 0)
            return Math.max(0, totalPackages - installedCount);
        return Updates.totalUpdates;
    }

    // Begin a run. The process starts immediately but blocks reading its stdin; the
    // popout shows a password field, and submitPassword() unblocks it.
    function start(): void {
        if (proc.running)
            return;
        root.phase = "password";
        root.totalPackages = 0;
        root.installedCount = 0;
        root.currentPackage = "";
        root.errorMessage = "";
        root._lines = [];
        root.logTail = "";
        proc.running = true;
    }

    // Feed the password to the waiting `sudo -S` on the process's stdin. The trailing
    // newline terminates sudo's read; on success the script proceeds to `paru`.
    function submitPassword(password: string): void {
        if (!proc.running || root.phase !== "password")
            return;
        proc.write(password + "\n");
        root.phase = "authenticating";
    }

    property bool _cancelling: false

    function cancel(): void {
        if (proc.running) {
            root._cancelling = true;
            proc.signal(15); // SIGTERM — script's trap tears down the sudo keep-alive
        }
    }

    // Clear a finished run's terminal state so the popout reverts to counts.
    function acknowledge(): void {
        if (root.finished)
            root.phase = "idle";
    }

    function _appendLog(line: string): void {
        const buf = root._lines;
        buf.push(line);
        if (buf.length > root._maxBuffer)
            buf.splice(0, buf.length - root._maxBuffer);
        root._lines = buf;
        root.logTail = buf.slice(-root._maxTail).join("\n");
    }

    function _handleLine(raw: string): void {
        // Qt's V4 JS engine lacks String.prototype.trimEnd; strip trailing CR/space
        // with a regex. String() guards against SplitParser handing back a non-string.
        // The run executes inside a pty (see symmetria-update.sh), which makes
        // makepkg emit ANSI colour codes regardless of --color flags — strip CSI
        // escape sequences so phase markers match and the log tail stays clean.
        const line = String(raw)
            .replace(/\x1B\[[0-9;?]*[A-Za-z]/g, "")
            .replace(/[\r\s]+$/, "");
        if (!line)
            return;

        // Control markers from the orchestrator script (exact "::phase:" / "::error:"
        // prefixes — pacman's own messages use ":: " with a space, so no collision).
        if (line.startsWith("::phase:")) {
            root.phase = line.substring("::phase:".length).trim();
            return;
        }
        if (line.startsWith("::error:")) {
            root.errorMessage = line.substring("::error:".length).trim();
            return;
        }

        // pacman transaction progress: "(12/42) upgrading firefox..."
        const m = line.match(/\((\d+)\/(\d+)\)\s+(upgrading|installing|reinstalling|downgrading)\s+(\S+)/);
        if (m) {
            root.phase = "installing";
            root.installedCount = parseInt(m[1]);
            root.totalPackages = parseInt(m[2]);
            root.currentPackage = m[4];
        } else if (/==>\s+Making package:/.test(line)) {
            // makepkg building an AUR package — no per-item number to count here.
            root.phase = "building";
            const bm = line.match(/Making package:\s+(\S+)/);
            if (bm)
                root.currentPackage = bm[1];
        }

        root._appendLog(line);
    }

    onPhaseChanged: {
        if (phase === "done") {
            Updates.refresh();        // recount so the indicator settles at the true value
            doneRevertTimer.restart(); // then revert the popout to the counts view
        }
        // On "error" we keep state so the popout can show errorMessage on next hover.
    }

    // After a successful run, briefly show "Everything is up to date", then revert
    // to the plain counts view. Errors are left for the user to dismiss explicitly.
    // If the post-run recount (checkupdates) is still in flight, keep holding the
    // done state — reverting early would flash the stale pre-update count.
    Timer {
        id: doneRevertTimer
        interval: 4000
        onTriggered: {
            if (Updates.updateInProgress) {
                interval = 1000; // poll until the recount lands
                restart();
            } else {
                interval = 4000;
                root.acknowledge();
            }
        }
    }

    Process {
        id: proc

        command: ["bash", root._script]
        stdinEnabled: true // we pipe the sudo password to the script's stdin

        stdout: SplitParser {
            onRead: data => root._handleLine(data)
        }

        onExited: (code, status) => {
            // User-initiated cancel: revert to idle quietly, no error state.
            if (root._cancelling) {
                root._cancelling = false;
                root.phase = "idle";
                return;
            }
            // The script emits ::phase:done/error before exiting; this is a safety
            // net if it died without emitting (e.g. killed externally).
            if (root.phase !== "done" && root.phase !== "error") {
                if (code !== 0)
                    root.errorMessage = root.errorMessage || qsTr("Update process exited unexpectedly (code %1)").arg(code);
                root.phase = code === 0 ? "done" : "error";
            }
        }
    }
}
