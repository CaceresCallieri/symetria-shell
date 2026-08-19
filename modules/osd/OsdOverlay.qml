pragma ComponentBehavior: Bound

import qs.components
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

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
                x: win.showing ? osdContent.x + slideTransform.x : 0
                y: win.showing ? osdContent.y : 0
                width: win.showing ? osdContent.width : 0
                height: win.showing ? osdContent.height : 0
            }

            // Brightness monitor for this screen
            readonly property Brightness.Monitor monitor: Brightness.getMonitorForScreen(modelData)

            // OSD state
            property bool showing: false
            property bool hovered: false
            property string activeMetric: "volume"
            property real volume
            property bool muted
            property real sourceVolume
            property bool sourceMuted
            property real brightness
            readonly property bool contentInteracting: content.interacting

            function anotherOverlayInteracting(): bool {
                for (const overlay of Visibilities.osdOverlays.values()) {
                    if (overlay !== win && overlay.contentInteracting)
                        return true;
                }
                return false;
            }

            function showAudioMetric(metric: string, enabled: bool): void {
                if (!enabled || Hypr.monitorFor(modelData) !== Hypr.focusedMonitor)
                    return;
                if (anotherOverlayInteracting())
                    return;
                if (!content.interacting)
                    activeMetric = metric;
                show();
            }

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

            Component.onCompleted: {
                volume = Audio.volume;
                muted = Audio.muted;
                sourceVolume = Audio.sourceVolume;
                sourceMuted = Audio.sourceMuted;
                brightness = monitor?.brightness ?? 0;

                Visibilities.osdOverlays.set(Hypr.monitorFor(modelData), win);
            }

            Component.onDestruction: {
                Visibilities.osdOverlays.delete(Hypr.monitorFor(modelData));
            }

            Connections {
                target: Audio

                function onVolumeChanged(): void {
                    win.volume = Audio.volume;
                    win.showAudioMetric("volume", true);
                }

                function onMutedChanged(): void {
                    win.muted = Audio.muted;
                    win.showAudioMetric("volume", true);
                }

                function onSourceVolumeChanged(): void {
                    win.sourceVolume = Audio.sourceVolume;
                    win.showAudioMetric("microphone", Config.osd.enableMicrophone);
                }

                function onSourceMutedChanged(): void {
                    win.sourceMuted = Audio.sourceMuted;
                    win.showAudioMetric("microphone", Config.osd.enableMicrophone);
                }
            }

            Connections {
                target: win.monitor

                function onBrightnessChanged(): void {
                    win.brightness = win.monitor?.brightness ?? 0;
                    if (!Config.osd.enableBrightness)
                        return;
                    if (!content.interacting)
                        win.activeMetric = "brightness";
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
                anchors.rightMargin: 0
                anchors.verticalCenter: parent.verticalCenter

                width: content.implicitWidth
                height: content.implicitHeight

                // opacity drives the Behavior animation; visible gates layout costs and the input Region mask
                opacity: win.showing ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    Anim {}
                }

                // Slide right-to-left on show, left-to-right on hide
                transform: Translate {
                    id: slideTransform

                    x: win.showing ? 0 : osdContent.width
                    Behavior on x {
                        Anim {}
                    }
                }

                Content {
                    id: content

                    anchors.fill: parent

                    monitor: win.monitor
                    activeMetric: win.activeMetric
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

        function _focusedOverlay(): var {
            const overlay = Visibilities.osdOverlays.get(Hypr.focusedMonitor);
            if (!overlay) console.warn("[OSD] No overlay for focused monitor");
            return overlay ?? null;
        }

        function toggle(): void { _focusedOverlay()?.toggle(); }
        function show(): void { _focusedOverlay()?.show(); }
        function hide(): void { _focusedOverlay()?.hide(); }

        function isVisible(): bool {
            return Visibilities.osdOverlays.get(Hypr.focusedMonitor)?.showing ?? false;
        }
    }
}
