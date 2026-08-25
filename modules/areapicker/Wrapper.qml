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

        function _openPicker(freeze: bool, clipboardOnly: bool, sshTransfer: bool): void {
            root.freeze = freeze;
            root.closing = false;
            root.clipboardOnly = clipboardOnly;
            root.sshTransfer = sshTransfer;
            root.activeAsync = true;
        }

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
            root._openPicker(false, false, false);
        }
        function openFreeze(): void {
            root._openPicker(true, false, false);
        }
        function openClip(): void {
            root._openPicker(false, true, false);
        }
        function openFreezeClip(): void {
            root._openPicker(true, true, false);
        }
    }

    IpcHandler {
        target: "screenshot"

        function region(): void {
            root._openPicker(false, false, true);
        }
        function regionFreeze(): void {
            root._openPicker(true, false, true);
        }

        function window(): void {
            ScreenshotTransfer.captureAndTransfer("window");
        }
        function monitor(): void {
            ScreenshotTransfer.captureAndTransfer("monitor");
        }
        function monitorSelect(): void {
            ScreenshotTransfer.captureAndTransfer("monitorSelect");
        }
        function keyboard(): void {
            ScreenshotTransfer.captureAndTransfer("keyboard");
        }
        function captureFirst(): void {
            ScreenshotTransfer.captureAndTransfer("captureFirst");
        }
    }

    CustomShortcut {
        name: "screenshot"
        description: "Open screenshot tool"
        onPressed: root._openPicker(false, false, false)
    }

    CustomShortcut {
        name: "screenshotFreeze"
        description: "Open screenshot tool (freeze mode)"
        onPressed: root._openPicker(true, false, false)
    }

    CustomShortcut {
        name: "screenshotClip"
        description: "Open screenshot tool (clipboard)"
        onPressed: root._openPicker(false, true, false)
    }

    CustomShortcut {
        name: "screenshotFreezeClip"
        description: "Open screenshot tool (freeze mode, clipboard)"
        onPressed: root._openPicker(true, true, false)
    }
}
