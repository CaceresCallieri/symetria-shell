pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import "services"

Scope {
    // Rate limiting: prevent phishing via rapid dialog spam
    property real lastCallTime: 0
    readonly property int rateLimitMs: 1000

    // FIFO path validation prefix - must match symmetria-askpass.sh
    readonly property string validFifoPrefix: "/tmp/symmetria-askpass-"

    IpcHandler {
        target: "askpass"

        function prompt(message: string, fifoPath: string, commandInfo: string): void {
            // Security: validate FIFO path to prevent writing to arbitrary files
            if (!fifoPath.startsWith(validFifoPrefix)) {
                console.error("Askpass: Invalid FIFO path rejected:", fifoPath);
                return;
            }

            // Security: reject path traversal attempts
            if (fifoPath.includes("..") || fifoPath.includes("\0")) {
                console.error("Askpass: Suspicious FIFO path rejected (traversal/null):", fifoPath);
                return;
            }

            // Security: reject unreasonably long paths (normal FIFO paths are ~40 chars)
            if (fifoPath.length > 128) {
                console.error("Askpass: FIFO path too long, rejected:", fifoPath.substring(0, 50) + "...");
                return;
            }

            // Security: only allow alphanumeric, dash, underscore, and dot after prefix
            const suffix = fifoPath.substring(validFifoPrefix.length);
            if (!/^[a-zA-Z0-9._-]+$/.test(suffix)) {
                console.error("Askpass: FIFO path contains invalid characters:", fifoPath);
                return;
            }

            // Rate limiting: reject rapid successive calls
            const now = Date.now();
            if (now - lastCallTime < rateLimitMs) {
                console.warn("Askpass: Rate limited, ignoring request");
                return;
            }
            lastCallTime = now;

            const command = commandInfo || "";
            console.log("Askpass: Prompt requested -", message, "Command:", command || "(none)");
            AskpassStore.show(message, fifoPath, command);
        }
    }
}
