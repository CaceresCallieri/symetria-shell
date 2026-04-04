pragma ComponentBehavior: Bound

import "modules/askpass/services"
import "modules/askpass"
import qs.components
import qs.services
import qs.config
import Quickshell
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: root

    // FIFO path validation prefix — must match symmetria-askpass.sh
    readonly property string _validFifoPrefix: "/tmp/symmetria-askpass-"

    function _validateFifo(path: string): bool {
        if (!path.startsWith(_validFifoPrefix)) {
            console.error("Askpass: Invalid FIFO path rejected:", path);
            return false;
        }
        if (path.includes("..") || path.includes("\0")) {
            console.error("Askpass: Suspicious FIFO path rejected (traversal/null):", path);
            return false;
        }
        if (path.length > 128) {
            console.error("Askpass: FIFO path too long:", path.substring(0, 50) + "...");
            return false;
        }
        const suffix = path.substring(_validFifoPrefix.length);
        if (!/^[a-zA-Z0-9._-]+$/.test(suffix)) {
            console.error("Askpass: FIFO path contains invalid characters:", path);
            return false;
        }
        return true;
    }

    Component.onCompleted: {
        const prompt = Quickshell.env("ASKPASS_PROMPT") || "Password:";
        const fifo = Quickshell.env("ASKPASS_FIFO") || "";
        const command = Quickshell.env("ASKPASS_COMMAND") || "";

        if (!fifo) {
            console.error("Askpass: ASKPASS_FIFO environment variable not set");
            Qt.quit();
            return;
        }

        if (!_validateFifo(fifo)) {
            Qt.quit();
            return;
        }

        AskpassStore.promptMessage = prompt;
        AskpassStore.fifoPath = fifo;
        AskpassStore.commandInfo = command;

        console.log("Askpass satellite: prompt =", prompt, "fifo =", fifo, "command =", command || "(none)");
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property ShellScreen modelData
            screen: modelData

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "symmetria-askpass"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            color: "transparent"

            // Scrim overlay
            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(Colours.palette.m3scrim, 0.4)
            }

            // Password dialog
            Content {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: parent.height * 0.3
            }
        }
    }
}
