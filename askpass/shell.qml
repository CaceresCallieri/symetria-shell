pragma ComponentBehavior: Bound

import "modules/askpass/services"
import "modules/askpass"
import qs.components
import qs.components.shapes
import qs.services
import qs.config
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes

ShellRoot {
    id: root

    // Shell detection — determines embedded vs standalone mode
    property bool shellRunning: false

    Process {
        id: shellCheck
        command: ["qs", "ipc", "--any-display", "-c", "symmetria", "call", "agentbar", "status"]
        running: true
        onExited: (code, status) => { root.shellRunning = (code === 0) }
    }

    // Bar height computation (mirrors BarWrapper.qml formula)
    readonly property int barHeight: {
        const padding = Math.max(Appearance.padding.smaller, Config.border.thickness);
        return Config.bar.sizes.innerWidth + padding * 2;
    }

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
    }

    // Brief defer to let Config's async FileView load user overrides
    // (transparency, sizing). 100ms is imperceptible but sufficient.
    property bool _configReady: false
    Timer {
        interval: 100
        running: true
        onTriggered: root._configReady = true
    }

    Variants {
        model: root._configReady ? Quickshell.screens : []

        PanelWindow {
            id: win

            required property ShellScreen modelData
            screen: modelData

            // Same layer as Drawers (Top) to avoid double-blur from compositor
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "symmetria-askpass"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            color: "transparent"

            // ── Standalone mode: scrim + centered dialog ──
            Rectangle {
                anchors.fill: parent
                visible: !root.shellRunning
                color: Qt.alpha(Colours.palette.m3scrim, 0.4)
            }

            Content {
                visible: !root.shellRunning
                embedded: false
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: parent.height * 0.3
            }

            // ── Embedded mode: top-hanging panel below bar ──
            Item {
                id: panelArea

                visible: root.shellRunning
                anchors.fill: parent
                // Offset below bar, minus border thickness since the satellite
                // doesn't render the shell's border that bridges bar-to-panel
                anchors.topMargin: root.barHeight - Config.border.thickness
                anchors.leftMargin: Config.border.thickness
                anchors.rightMargin: Config.border.thickness

                // Animated wrapper — slides down from bar like the old Wrapper.qml
                Item {
                    id: animWrapper

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    implicitWidth: embeddedContent.implicitWidth
                    implicitHeight: 0
                    clip: true

                    // Slide-down reveal animation
                    Component.onCompleted: showAnim.start()

                    SequentialAnimation {
                        id: showAnim

                        Anim {
                            target: animWrapper
                            property: "implicitHeight"
                            to: embeddedContent.implicitHeight
                            duration: Appearance.anim.durations.expressiveDefaultSpatial
                            easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
                        }
                        ScriptAction {
                            script: animWrapper.implicitHeight = Qt.binding(() => embeddedContent.implicitHeight)
                        }
                    }

                    // Content anchored to bottom — reveals from top as wrapper grows
                    Content {
                        id: embeddedContent
                        embedded: true
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                // Background shape — single-shape, no overlap, so direct alpha is safe
                Shape {
                    id: bgShape

                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    TopHangingBackground {
                        wrapper: animWrapper
                        startX: (bgShape.width - animWrapper.width) / 2 - rounding
                        startY: 0
                        customFillColor: Qt.alpha(
                            Colours.generalBackgroundOpaque,
                            Colours.generalBackgroundAlpha * (Colours.transparency.enabled ? Colours.transparency.base : 1)
                        )
                    }
                }
            }
        }
    }
}
