pragma ComponentBehavior: Bound

import qs.components.containers
import qs.components.misc
import qs.services
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

Scope {
    LazyLoader {
        id: root

        property bool freeze
        property bool closing
        property bool clipboardOnly
        property bool sshTransfer

        Variants {
            model: Quickshell.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData

                screen: modelData
                name: "area-picker"
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: root.closing ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
                mask: root.closing ? empty : null

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                Region {
                    id: empty
                }

                Picker {
                    loader: root
                    screen: win.modelData
                }
            }
        }
    }

    IpcHandler {
        target: "picker"

        function open(): void {
            root.freeze = false;
            root.closing = false;
            root.clipboardOnly = false;
            root.sshTransfer = false;
            root.activeAsync = true;
        }

        function openFreeze(): void {
            root.freeze = true;
            root.closing = false;
            root.clipboardOnly = false;
            root.sshTransfer = false;
            root.activeAsync = true;
        }

        function openClip(): void {
            root.freeze = false;
            root.closing = false;
            root.clipboardOnly = true;
            root.sshTransfer = false;
            root.activeAsync = true;
        }

        function openFreezeClip(): void {
            root.freeze = true;
            root.closing = false;
            root.clipboardOnly = true;
            root.sshTransfer = false;
            root.activeAsync = true;
        }
    }

    IpcHandler {
        target: "screenshot"

        function region(): void {
            root.freeze = false;
            root.closing = false;
            root.clipboardOnly = false;
            root.sshTransfer = true;
            root.activeAsync = true;
        }

        function regionFreeze(): void {
            root.freeze = true;
            root.closing = false;
            root.clipboardOnly = false;
            root.sshTransfer = true;
            root.activeAsync = true;
        }

        function window(): void { ScreenshotTransfer.captureAndTransfer("window") }
        function monitor(): void { ScreenshotTransfer.captureAndTransfer("monitor") }
        function monitorSelect(): void { ScreenshotTransfer.captureAndTransfer("monitorSelect") }
        function keyboard(): void { ScreenshotTransfer.captureAndTransfer("keyboard") }
        function captureFirst(): void { ScreenshotTransfer.captureAndTransfer("captureFirst") }
    }

    CustomShortcut {
        name: "screenshot"
        description: "Open screenshot tool"
        onPressed: {
            root.freeze = false;
            root.closing = false;
            root.clipboardOnly = false;
            root.sshTransfer = false;
            root.activeAsync = true;
        }
    }

    CustomShortcut {
        name: "screenshotFreeze"
        description: "Open screenshot tool (freeze mode)"
        onPressed: {
            root.freeze = true;
            root.closing = false;
            root.clipboardOnly = false;
            root.sshTransfer = false;
            root.activeAsync = true;
        }
    }

    CustomShortcut {
        name: "screenshotClip"
        description: "Open screenshot tool (clipboard)"
        onPressed: {
            root.freeze = false;
            root.closing = false;
            root.clipboardOnly = true;
            root.sshTransfer = false;
            root.activeAsync = true;
        }
    }

    CustomShortcut {
        name: "screenshotFreezeClip"
        description: "Open screenshot tool (freeze mode, clipboard)"
        onPressed: {
            root.freeze = true;
            root.closing = false;
            root.clipboardOnly = true;
            root.sshTransfer = false;
            root.activeAsync = true;
        }
    }
}
