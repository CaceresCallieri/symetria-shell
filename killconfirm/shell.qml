pragma ComponentBehavior: Bound

import "modules/killconfirm"
import qs.components
import qs.components.containers
import qs.components.misc
import qs.services
import qs.config
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: root

    // Window info captured by the launch script at keybind time.
    // Using PID instead of forcekillactive ensures we kill the correct
    // process even if focus changes during satellite startup.
    readonly property string windowTitle: Quickshell.env("KILLCONFIRM_TITLE") || "Unknown window"
    readonly property string windowClass: Quickshell.env("KILLCONFIRM_CLASS") || ""
    readonly property string windowPid: Quickshell.env("KILLCONFIRM_PID") || ""

    Component.onCompleted: {
        if (!windowPid) {
            console.error("KillConfirm: KILLCONFIRM_PID not set");
            Qt.quit();
            return;
        }
    }

    function confirm(): void {
        if (killProcess.running) return;
        killProcess.running = true;
    }

    function dismiss(): void {
        Qt.quit();
    }

    Process {
        id: killProcess
        command: ["kill", "-9", root.windowPid]
        onExited: (code, status) => {
            if (code !== 0)
                console.warn("KillConfirm: kill -9 exited with code", code, "(process may have already exited)");
            Qt.quit();
        }
    }

    // Brief defer to let Config's async FileView load user overrides
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

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "symmetria-killconfirm"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            color: "transparent"
            visible: true

            mask: Region {
                x: 0; y: 0
                width: win.width
                height: win.height
            }

            // Entry animation — starts hidden, animates in
            property bool contentReady: false
            Component.onCompleted: contentReady = true

            property real dialogOpacity: contentReady ? 1.0 : 0.0
            property real dialogScale: contentReady ? 1.0 : 0.0

            Behavior on dialogOpacity {
                NumberAnimation {
                    duration: Appearance.anim.durations.normal * 0.75
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on dialogScale {
                NumberAnimation {
                    duration: Appearance.anim.durations.large * 0.75
                    easing.type: Easing.OutBack
                }
            }

            FocusManager {
                active: win.contentReady
                target: content
            }

            // Click outside dialog to dismiss
            MouseArea {
                anchors.fill: parent
                onClicked: root.dismiss()
            }

            // Dialog wrapper with entry animation
            Item {
                anchors.centerIn: parent
                width: content.implicitWidth
                height: content.implicitHeight
                scale: win.dialogScale
                opacity: win.dialogOpacity

                Content {
                    id: content
                    windowTitle: root.windowTitle
                    windowClass: root.windowClass
                    onConfirmRequested: root.confirm()
                    onDismissRequested: root.dismiss()
                }
            }
        }
    }
}
