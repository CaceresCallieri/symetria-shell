pragma Singleton

import qs.config
import qs.utils
import Symmetria
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string toastKey: "screenshot-transfer"
    readonly property string screenshotDir: `${Paths.pictures}/Screenshots`

    // --- Keyboard mode state machine ---
    // 0 = idle, 1 = selecting tile A, 2 = selecting tile B
    property int _kbptrState: 0
    property var _tileA: null
    // Capture metadata carried across async Process boundaries
    property string _pendingLocalPath: ""
    property string _pendingRemotePath: ""

    // --- Public API ---

    // Transfer an already-captured local file to the remote host.
    // Called by the area picker after its own capture completes.
    function _checkSshConfig(): bool {
        if (!Config.screenshot.ssh.enabled) {
            Toaster.toast(qsTr("SSH transfer disabled"), qsTr("Enable in shell.json → screenshot.ssh.enabled"),
                "cloud_off", Toast.Warning, 0, "", root.toastKey);
            return false;
        }
        if (!Config.screenshot.ssh.host) {
            Toaster.toast(qsTr("SSH host not configured"),
                qsTr("Set shell.json → screenshot.ssh.host"),
                "cloud_off", Toast.Error, 0, "", root.toastKey);
            return false;
        }
        return true;
    }

    function transfer(localPath: string): void {
        if (!_checkSshConfig())
            return;
        const timestamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss");
        const remotePath = `${Config.screenshot.ssh.remoteDir}/screenshot-${timestamp}.png`;
        _doTransfer(localPath, remotePath);
    }

    // Full capture-and-transfer pipeline for non-picker modes.
    function captureAndTransfer(mode: string): void {
        if (!_checkSshConfig())
            return;

        const timestamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss");
        const filename = `screenshot_${timestamp}.png`;
        const localPath = `${root.screenshotDir}/${filename}`;
        const remotePath = `${Config.screenshot.ssh.remoteDir}/screenshot-${timestamp}.png`;

        root._pendingLocalPath = localPath;
        root._pendingRemotePath = remotePath;

        Toaster.toast(qsTr("Capturing screenshot\u2026"), _modeLabel(mode),
            "photo_camera", Toast.Info, -1, "", root.toastKey);

        switch (mode) {
        case "window":
            _startHyprshot(["hyprshot", "-m", "window", "-m", "active",
                "-o", root.screenshotDir, "-f", filename, "-s"]);
            break;
        case "monitor":
            _startHyprshot(["hyprshot", "-m", "output", "-m", "active",
                "-o", root.screenshotDir, "-f", filename, "-s"]);
            break;
        case "monitorSelect":
            _startHyprshot(["hyprshot", "-m", "output",
                "-o", root.screenshotDir, "-f", filename, "-s"]);
            break;
        case "captureFirst":
            _startCaptureFirst(localPath);
            break;
        case "keyboard":
            _startKeyboardCapture();
            break;
        default:
            console.warn(`[ScreenshotTransfer] Unknown mode: ${mode}`);
            Toaster.toast(qsTr("Unknown mode"), mode, "error", Toast.Error, 0, "", root.toastKey);
        }
    }

    // --- Transfer pipeline ---

    function _doTransfer(localPath: string, remotePath: string): void {
        Toaster.toast(qsTr("Sending screenshot to %1\u2026").arg(Config.screenshot.ssh.host),
            qsTr("Transferring image via SSH"), "cloud_upload", Toast.Info, -1, "", root.toastKey);

        root._pendingLocalPath = localPath;
        root._pendingRemotePath = remotePath;
        transferProcess.command = ["scp", localPath, `${Config.screenshot.ssh.host}:${remotePath}`];
        transferProcess.running = true;
    }

    readonly property Process transferProcess: Process {
        onExited: (exitCode, exitStatus) => {
            ProcessUtils.logExit("ScreenshotTransfer", "ssh-transfer", exitCode, "");
            if (exitCode === 0) {
                // Copy remote path to clipboard
                Quickshell.execDetached(["wl-copy", root._pendingRemotePath]);
                Toaster.toast(qsTr("Screenshot sent to %1").arg(Config.screenshot.ssh.host),
                    qsTr("Remote path copied to clipboard"), "cloud_done",
                    Toast.Success, 0, "", root.toastKey);
            } else {
                // Fallback: copy local path to clipboard
                Quickshell.execDetached(["wl-copy", root._pendingLocalPath]);
                Toaster.toast(qsTr("Transfer failed"),
                    qsTr("Could not reach %1 — local path copied").arg(Config.screenshot.ssh.host),
                    "cloud_off", Toast.Error, 0, "", root.toastKey);
            }
        }

        stderr: StdioCollector {
            onStreamFinished: ProcessUtils.logStderr("ScreenshotTransfer", "ssh-transfer", text)
        }
    }

    // --- Hyprshot capture (window, monitor, monitorSelect) ---

    function _startHyprshot(cmd: list<string>): void {
        captureProcess.command = cmd;
        captureProcess.running = true;
    }

    readonly property Process captureProcess: Process {
        onExited: (exitCode, exitStatus) => {
            ProcessUtils.logExit("ScreenshotTransfer", "hyprshot", exitCode, "");
            // hyprshot returns non-zero on cancel; check for file existence
            fileCheckProcess.command = ["test", "-f", root._pendingLocalPath];
            fileCheckProcess.running = true;
        }

        stderr: StdioCollector {
            onStreamFinished: ProcessUtils.logStderr("ScreenshotTransfer", "hyprshot", text)
        }
    }

    readonly property Process fileCheckProcess: Process {
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root._doTransfer(root._pendingLocalPath, root._pendingRemotePath);
            } else {
                Toaster.toast(qsTr("Screenshot cancelled"), qsTr("No image was captured"),
                    "close", Toast.Warning, 0, "", root.toastKey);
            }
        }
    }

    // --- Capture-first mode (grim → swappy → transfer) ---

    function _startCaptureFirst(localPath: string): void {
        const tempFile = `/tmp/symmetria-screenshot-full-${Date.now()}.png`;
        grimFullProcess._tempPath = tempFile;
        grimFullProcess._outputPath = localPath;
        grimFullProcess.command = ["grim", tempFile];
        grimFullProcess.running = true;
    }

    readonly property Process grimFullProcess: Process {
        property string _tempPath: ""
        property string _outputPath: ""

        onExited: (exitCode, exitStatus) => {
            ProcessUtils.logExit("ScreenshotTransfer", "grim-full", exitCode, "");
            if (exitCode !== 0) {
                Toaster.toast(qsTr("Capture failed"), qsTr("grim could not capture screen"),
                    "broken_image", Toast.Error, 0, "", root.toastKey);
                return;
            }
            // Open swappy for editing/cropping — output goes to the final path
            swappyProcess._tempPath = _tempPath;
            swappyProcess.command = ["swappy", "-f", _tempPath, "-o", _outputPath];
            swappyProcess.running = true;
        }

        stderr: StdioCollector {
            onStreamFinished: ProcessUtils.logStderr("ScreenshotTransfer", "grim-full", text)
        }
    }

    readonly property Process swappyProcess: Process {
        property string _tempPath: ""

        onExited: (exitCode, exitStatus) => {
            // Clean up full-screen temp capture
            if (_tempPath)
                Quickshell.execDetached(["rm", "-f", _tempPath]);

            ProcessUtils.logExit("ScreenshotTransfer", "swappy", exitCode, "");
            if (exitCode !== 0) {
                Toaster.toast(qsTr("Screenshot cancelled"), qsTr("Editor was closed without saving"),
                    "close", Toast.Warning, 0, "", root.toastKey);
                return;
            }
            // Check if swappy wrote the output file
            fileCheckProcess.command = ["test", "-f", root._pendingLocalPath];
            fileCheckProcess.running = true;
        }

        stderr: StdioCollector {
            onStreamFinished: ProcessUtils.logStderr("ScreenshotTransfer", "swappy", text)
        }
    }

    // --- Keyboard mode (wl-kbptr × 2 → grim → transfer) ---

    function _startKeyboardCapture(): void {
        root._kbptrState = 1;
        root._tileA = null;
        kbptrProcess.running = true;
    }

    readonly property Process kbptrProcess: Process {
        command: ["wl-kbptr", "--only-print", "-o", "modes=tile", "-o", "cancellation_status_code=2"]

        stdout: StdioCollector { id: kbptrStdout }

        stderr: StdioCollector {
            onStreamFinished: ProcessUtils.logStderr("ScreenshotTransfer", "wl-kbptr", text)
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 2) {
                root._kbptrState = 0;
                Toaster.toast(qsTr("Screenshot cancelled"), qsTr("Selection was cancelled"),
                    "close", Toast.Warning, 0, "", root.toastKey);
                return;
            }
            if (exitCode !== 0) {
                root._kbptrState = 0;
                Toaster.toast(qsTr("Screenshot failed"), qsTr("wl-kbptr exited with an error"),
                    "broken_image", Toast.Error, 0, "", root.toastKey);
                return;
            }

            const output = kbptrStdout.text.trim();
            if (!output) {
                root._kbptrState = 0;
                Toaster.toast(qsTr("Screenshot cancelled"), qsTr("No tile selected"),
                    "close", Toast.Warning, 0, "", root.toastKey);
                return;
            }

            const tile = root._parseTile(output);
            if (!tile) {
                root._kbptrState = 0;
                Toaster.toast(qsTr("Screenshot failed"), qsTr("Could not parse tile output"),
                    "broken_image", Toast.Error, 0, "", root.toastKey);
                return;
            }

            if (root._kbptrState === 1) {
                root._tileA = tile;
                root._kbptrState = 2;
                kbptrProcess.running = true;
            } else if (root._kbptrState === 2) {
                root._kbptrState = 0;
                const bounds = root._computeBounds(root._tileA, tile);
                if (bounds.w <= 0 || bounds.h <= 0) {
                    Toaster.toast(qsTr("Screenshot cancelled"),
                        qsTr("Invalid region: %1x%2").arg(bounds.w).arg(bounds.h),
                        "close", Toast.Warning, 0, "", root.toastKey);
                    return;
                }
                grimRegionProcess.command = ["grim", "-g",
                    `${bounds.x},${bounds.y} ${bounds.w}x${bounds.h}`,
                    root._pendingLocalPath];
                grimRegionProcess.running = true;
            }
        }
    }

    readonly property Process grimRegionProcess: Process {
        onExited: (exitCode, exitStatus) => {
            ProcessUtils.logExit("ScreenshotTransfer", "grim-region", exitCode, "");
            if (exitCode === 0) {
                root._doTransfer(root._pendingLocalPath, root._pendingRemotePath);
            } else {
                Toaster.toast(qsTr("Capture failed"), qsTr("grim could not capture region"),
                    "broken_image", Toast.Error, 0, "", root.toastKey);
            }
        }

        stderr: StdioCollector {
            onStreamFinished: ProcessUtils.logStderr("ScreenshotTransfer", "grim-region", text)
        }
    }

    // --- Helpers ---

    function _modeLabel(mode: string): string {
        switch (mode) {
        case "window": return qsTr("Active window");
        case "monitor": return qsTr("Active monitor");
        case "monitorSelect": return qsTr("Select monitor");
        case "captureFirst": return qsTr("Capture & crop");
        case "keyboard": return qsTr("Keyboard selection");
        default: return mode;
        }
    }

    // Parse wl-kbptr output: "WxH+relX+relY +outX+outY ..."
    // Returns { x1, y1, x2, y2 } in absolute coordinates, or null on failure.
    function _parseTile(output: string): var {
        const match = output.match(/^(\d+)x(\d+)\+(\d+)\+(\d+)\s+\+(\d+)\+(\d+)\s/);
        if (!match) return null;

        const w = parseInt(match[1]);
        const h = parseInt(match[2]);
        const relX = parseInt(match[3]);
        const relY = parseInt(match[4]);
        const outX = parseInt(match[5]);
        const outY = parseInt(match[6]);

        const x1 = relX + outX;
        const y1 = relY + outY;
        return { x1: x1, y1: y1, x2: x1 + w, y2: y1 + h };
    }

    // Compute the bounding box of two tiles.
    function _computeBounds(a: var, b: var): var {
        const x = Math.min(a.x1, b.x1);
        const y = Math.min(a.y1, b.y1);
        const x2 = Math.max(a.x2, b.x2);
        const y2 = Math.max(a.y2, b.y2);
        return { x: x, y: y, w: x2 - x, h: y2 - y };
    }

    // Ensure the screenshot directory exists on first use.
    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", root.screenshotDir]);
    }
}
