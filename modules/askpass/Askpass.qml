pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io

Scope {
    AskpassWindow {
        id: askpassWin
    }

    IpcHandler {
        target: "askpass"

        // Rate limiting: prevent phishing via rapid dialog spam
        property real lastCallTime: 0
        readonly property int rateLimitMs: 1000

        // FIFO path validation prefix - must match caelestia-askpass.sh
        readonly property string validFifoPrefix: "/tmp/caelestia-askpass-"

        function prompt(message: string, fifoPath: string): void {
            // Security: validate FIFO path to prevent writing to arbitrary files
            if (!fifoPath.startsWith(validFifoPrefix)) {
                console.error("Askpass: Invalid FIFO path rejected:", fifoPath);
                return;
            }

            // Rate limiting: reject rapid successive calls
            const now = Date.now();
            if (now - lastCallTime < rateLimitMs) {
                console.warn("Askpass: Rate limited, ignoring request");
                return;
            }
            lastCallTime = now;

            console.log("Askpass: Prompt requested -", message);
            askpassWin.show(message, fifoPath);
        }
    }
}
