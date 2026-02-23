pragma Singleton

import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Prompt state - set by IPC handler, read by Content
    property string promptMessage: ""
    property string fifoPath: ""
    property string passwordBuffer: ""
    property string commandInfo: ""

    function show(message: string, fifo: string, command: string): void {
        // Clear sensitive data FIRST, before dialog becomes visible
        root.passwordBuffer = "";
        root.promptMessage = message || "Password:";
        root.fifoPath = fifo;
        root.commandInfo = command || "";

        // Toggle visibility on all screens
        for (const [_, visibilities] of Visibilities.screens) {
            visibilities.askpass = true;
        }

        console.log("Askpass: Dialog shown for FIFO:", fifo);
    }

    function hide(): void {
        // Hide on all screens
        for (const [_, visibilities] of Visibilities.screens) {
            visibilities.askpass = false;
        }

        root.promptMessage = "";
        root.fifoPath = "";
        root.commandInfo = "";
    }

    function submitPassword(password: string): void {
        if (!root.fifoPath) {
            root.hide();
            return;
        }

        writeProcess.fifoPath = root.fifoPath;
        writeProcess.password = password;
        writeProcess.running = true;
    }

    function cancel(): void {
        // Write empty string to unblock the reading process
        if (root.fifoPath) {
            cancelProcess.fifoPath = root.fifoPath;
            cancelProcess.running = true;
        } else {
            root.hide();
        }
    }

    Process {
        id: writeProcess

        property string fifoPath: ""
        property string password: ""

        // Use printf with shell-escaped password to safely write to FIFO
        // printf '%s' avoids adding a trailing newline which would break password
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
            root.hide();
        }
    }

    Timer {
        id: writeTimeout
        interval: 5000  // 5 second timeout
        onTriggered: {
            console.error("Askpass: Write timeout - forcing close");
            writeProcess.signal(9);
            root.hide();
        }
    }

    Process {
        id: cancelProcess

        property string fifoPath: ""

        // Write sentinel value to signal cancellation
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
            root.hide();
        }
    }

    Timer {
        id: cancelTimeout
        interval: 5000  // 5 second timeout
        onTriggered: {
            console.error("Askpass: Cancel timeout - forcing close");
            cancelProcess.signal(9);
            root.hide();
        }
    }
}
