pragma ComponentBehavior: Bound

import qs.components
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects

/// Standalone OSD overlay on WlrLayer.Overlay.
///
/// Renders above fullscreen windows (unlike the former drawer-based OSD on WlrLayer.Top).
/// Triggers via volume/brightness key changes (always) and right-edge hover (non-fullscreen,
/// driven by Interactions.qml in the Drawers module via Visibilities.osdOverlays).
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData

            screen: modelData
            name: "osd-overlay"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            // Click-through when hidden, content area when visible (enables hover + scroll).
            // Always bound to contentRegion so geometry changes re-evaluate the mask.
            mask: contentRegion

            Region {
                id: contentRegion
                x: osdContent.visible ? osdContent.x : 0
                y: osdContent.visible ? osdContent.y : 0
                width: osdContent.visible ? osdContent.width : 0
                height: osdContent.visible ? osdContent.height : 0
            }

            // Per-screen visibilities from Drawers' PersistentProperties.
            // Content.qml uses visibilities.session to decide mic slider visibility.
            readonly property var screenVisibilities: Visibilities.getForMonitor(Hypr.monitorFor(modelData))

            // Brightness monitor for this screen
            readonly property Brightness.Monitor monitor: Brightness.getMonitorForScreen(modelData)

            // OSD state
            property bool showing: false
            property bool hovered: false
            property real volume
            property bool muted
            property real sourceVolume
            property bool sourceMuted
            property real brightness

            function show(): void {
                if (!Config.osd.enabled) return;
                showing = true;
                autoHideTimer.restart();
            }

            function hide(): void {
                showing = false;
            }

            function toggle(): void {
                if (showing) hide();
                else show();
            }

            readonly property bool isShowing: showing

            Component.onCompleted: {
                volume = Audio.volume;
                muted = Audio.muted;
                sourceVolume = Audio.sourceVolume;
                sourceMuted = Audio.sourceMuted;
                brightness = monitor?.brightness ?? 0;

                Visibilities.osdOverlays.set(Hypr.monitorFor(modelData), win);
                Visibilities.osdVersion++;
            }

            Component.onDestruction: {
                Visibilities.osdOverlays.delete(Hypr.monitorFor(modelData));
                Visibilities.osdVersion++;
            }

            Connections {
                target: Audio

                function onVolumeChanged(): void {
                    win.volume = Audio.volume;
                    win.show();
                }

                function onMutedChanged(): void {
                    win.muted = Audio.muted;
                    win.show();
                }

                function onSourceVolumeChanged(): void {
                    win.sourceVolume = Audio.sourceVolume;
                    win.show();
                }

                function onSourceMutedChanged(): void {
                    win.sourceMuted = Audio.sourceMuted;
                    win.show();
                }
            }

            Connections {
                target: win.monitor

                function onBrightnessChanged(): void {
                    win.brightness = win.monitor?.brightness ?? 0;
                    win.show();
                }
            }

            Timer {
                id: autoHideTimer

                interval: Config.osd.hideDelay
                onTriggered: {
                    if (!win.hovered)
                        win.hide();
                }
            }

            // OSD content — right-aligned, vertically centered
            Item {
                id: osdContent

                anchors.right: parent.right
                anchors.rightMargin: Config.border.thickness
                anchors.verticalCenter: parent.verticalCenter

                width: content.implicitWidth
                height: content.implicitHeight

                opacity: win.showing ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    Anim {}
                }

                // Background with shadow and transparency.
                // Two-layer approach matches Drawers.qml: outer layer applies
                // transparency + shadow, inner layer renders shapes at full opacity.
                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    opacity: Colours.transparency.enabled ? Colours.transparency.base : 1
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        blurMax: 15
                        shadowColor: Qt.alpha(Colours.palette.m3shadow, 0.7)
                    }

                    Item {
                        anchors.fill: parent
                        layer.enabled: true
                        opacity: Colours.generalBackgroundAlpha

                        Rectangle {
                            anchors.fill: parent
                            color: Colours.generalBackgroundOpaque
                            radius: Config.border.rounding
                        }
                    }
                }

                Content {
                    id: content

                    anchors.fill: parent

                    monitor: win.monitor
                    visibilities: win.screenVisibilities ?? ({session: false})
                    volume: win.volume
                    muted: win.muted
                    sourceVolume: win.sourceVolume
                    sourceMuted: win.sourceMuted
                    brightness: win.brightness
                }

                // Hover detection without consuming wheel/click events.
                // Pauses auto-hide while cursor is over the OSD content.
                HoverHandler {
                    onHoveredChanged: {
                        win.hovered = hovered;
                        if (hovered)
                            autoHideTimer.stop();
                        else if (win.showing)
                            autoHideTimer.restart();
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "osd"

        function toggle(): void {
            const overlay = Visibilities.osdOverlays.get(Hypr.focusedMonitor);
            if (overlay) overlay.toggle();
            else console.warn("[OSD] No overlay for focused monitor");
        }

        function show(): void {
            const overlay = Visibilities.osdOverlays.get(Hypr.focusedMonitor);
            if (overlay) overlay.show();
            else console.warn("[OSD] No overlay for focused monitor");
        }

        function hide(): void {
            const overlay = Visibilities.osdOverlays.get(Hypr.focusedMonitor);
            if (overlay) overlay.hide();
            else console.warn("[OSD] No overlay for focused monitor");
        }

        function isVisible(): bool {
            return Visibilities.osdOverlays.get(Hypr.focusedMonitor)?.isShowing ?? false;
        }
    }
}
