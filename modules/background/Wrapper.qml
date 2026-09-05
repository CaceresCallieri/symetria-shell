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

            // Frozen metal sheet: the focus-mode BACKDROP. Fades in while the
            // image stack fades out — both driven by the same focusMode flip
            // and the same Anim duration, so it is a crossfade. Sits
            // underneath, so the images win visually at every point of the
            // fade. Loader-gated so nothing instantiates while the feature is
            // disabled in config.
            Loader {
                anchors.fill: parent
                active: Config.background.focusBackdrop.enabled
                asynchronous: true

                // Ready gating: focus mode persists across restarts, so the
                // loader can be born with focus already on — hold at 0 until
                // the component exists and let the fade play properly.
                // visible follows opacity so the frozen shader costs nothing
                // while fully faded out.
                opacity: Wallpapers.focusMode && status === Loader.Ready ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    Anim {}
                }

                sourceComponent: MetalWallpaper {}
            }

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
