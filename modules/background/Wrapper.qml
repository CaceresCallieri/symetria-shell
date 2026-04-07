pragma ComponentBehavior: Bound

import qs.components
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import Quickshell.Wayland
import QtQuick

Loader {
    asynchronous: true
    active: Config.background.enabled

    sourceComponent: Variants {
        model: Quickshell.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData

            screen: modelData
            name: "background"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            color: Colours.palette.m3surface

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Item {
                anchors.fill: parent
                opacity: Wallpapers.wallpaperVisible ? 1 : 0

                Behavior on opacity {
                    Anim {}
                }

                Wallpaper {
                    id: wallpaper
                    screen: win.modelData
                }

                Visualiser {
                    anchors.fill: parent
                    screen: win.modelData
                    wallpaper: wallpaper
                }

                Loader {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Appearance.padding.large

                    active: Config.background.desktopClock.enabled
                    asynchronous: true

                    source: "DesktopClock.qml"
                }
            }
        }
    }
}
