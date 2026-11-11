pragma ComponentBehavior: Bound

import qs.components.containers
import qs.components.misc
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Scope {
    IpcHandler {
        target: "screenshare"

        function open(path: string, token: string): string {
            return ScreenShare.open(path, token);
        }

        function status(): string {
            return JSON.stringify({
                ready: true,
                active: ScreenShare.active || ScreenShare.connecting
            });
        }
    }

    LazyLoader {
        active: ScreenShare.active

        Variants {
            model: Quickshell.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData
                readonly property bool shouldShow: ScreenShare.active && ScreenShare.context.placement?.monitor === modelData.name

                name: "screenshare"
                screen: modelData
                visible: shouldShow
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.keyboardFocus: shouldShow ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                Rectangle {
                    anchors.fill: parent
                    color: "#99000000"
                    MouseArea {
                        anchors.fill: parent
                        onClicked: ScreenShare.cancel()
                    }
                }

                Loader {
                    id: contentLoader
                    active: win.shouldShow
                    x: ScreenShare.context.placement?.x ?? 0
                    y: ScreenShare.context.placement?.y ?? 0
                    width: Math.min(win.width, ScreenShare.context.placement?.width ?? win.width * 0.9)
                    height: Math.min(win.height, ScreenShare.context.placement?.height ?? win.height * 0.9)
                    sourceComponent: Content {}
                }

                FocusManager {
                    active: win.shouldShow && contentLoader.status === Loader.Ready
                    target: (contentLoader.item as Item) ?? contentLoader
                }
            }
        }
    }
}
