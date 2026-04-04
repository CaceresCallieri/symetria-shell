pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Prompt state — set by shell.qml from environment variables
    property string promptMessage: ""
    property string fifoPath: ""
    property string passwordBuffer: ""
    property string commandInfo: ""

    function submitPassword(password: string): void {
        if (!root.fifoPath) {
            Qt.quit();
            return;
        }
        // Guard against double-submit (e.g. button double-click or Enter + button)
        if (writeProcess.running) return;

        writeProcess.fifoPath = root.fifoPath;
        writeProcess.password = password;
        writeProcess.running = true;
    }

    function cancel(): void {
        if (root.fifoPath) {
            // Guard against double-cancel
            if (cancelProcess.running) return;
            cancelProcess.fifoPath = root.fifoPath;
            cancelProcess.running = true;
        } else {
            Qt.quit();
        }
    }

    Process {
        id: writeProcess

        property string fifoPath: ""
        property string password: ""

        // printf '%s' avoids adding a trailing newline which would break password
        // Sentinel for cancel: '__CANCELLED__' — must match symmetria-askpass.sh:65
        command: ["sh", "-c", "printf '%s' \"$1\" > \"$2\"", "--", password, fifoPath]

        onRunningChanged: {
            if (running) writeTimeout.start();
            else writeTimeout.stop();
        }

        onExited: (exitCode, exitStatus) => {
            writeTimeout.stop();
            if (exitCode !== 0) {
                console.error("Askpass: Write failed with exitCode:", exitCode);
            } else {
                console.log("Askpass: Password submitted successfully");
            }
            Qt.quit();
        }
    }

    Timer {
        id: writeTimeout
        interval: 5000
        onTriggered: {
            console.error("Askpass: Write timeout - forcing close");
            writeProcess.signal(9);
            Qt.quit();
        }
    }

    Process {
        id: cancelProcess

        property string fifoPath: ""

        // Sentinel '__CANCELLED__' must match symmetria-askpass.sh:65
        command: ["sh", "-c", "printf '%s' '__CANCELLED__' > \"$1\"", "--", fifoPath]

        onRunningChanged: {
            if (running) cancelTimeout.start();
            else cancelTimeout.stop();
        }

        onExited: (exitCode, exitStatus) => {
            cancelTimeout.stop();
            if (exitCode !== 0) {
                console.error("Askpass: Cancel write failed with exitCode:", exitCode);
            } else {
                console.log("Askpass: Cancellation sent");
            }
            Qt.quit();
        }
    }

    Timer {
        id: cancelTimeout
        interval: 5000
        onTriggered: {
            console.error("Askpass: Cancel timeout - forcing close");
            cancelProcess.signal(9);
            Qt.quit();
        }
    }
}
