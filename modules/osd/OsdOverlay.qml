pragma ComponentBehavior: Bound

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
///
/// TWO INDEPENDENT CARDS, not one card that switches metric: audio above the
/// screen's centre, brightness below, each owning its own visibility and timer.
/// Raising one never dismisses the other, so a volume nudge followed by a
/// brightness nudge leaves both standing.
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

            // Declared at the BOTTOM of this object, after both cards exist —
            // see the note there.
            mask: maskRegion

            // Brightness monitor for this screen
            readonly property Brightness.Monitor monitor: Brightness.getMonitorForScreen(modelData)

            property real volume
            property bool muted
            property real sourceVolume
            property bool sourceMuted
            property real brightness

            /// The upper card carries whichever audio metric last moved. Volume
            /// and microphone share one spot because they are the same kind of
            /// thing; brightness gets its own.
            property string audioMetric: "volume"

            /// How far each card sits from the screen's vertical centre. A quarter
            /// of the trigger strip is half a zone, which centres each card inside
            /// the zone that summons it. Panels.qml splits the same
            /// Config.osd.triggerHeight into those zones — the /4 here and the /2
            /// there are one derivation, not two constants.
            readonly property real metricOffset: Config.osd.triggerHeight / 4

            readonly property bool showing: audioCard.showing || brightnessCard.showing
            readonly property bool contentInteracting: audioCard.interacting || brightnessCard.interacting

            function anotherOverlayInteracting(): bool {
                for (const overlay of Visibilities.osdOverlays.values()) {
                    if (overlay !== win && overlay.contentInteracting)
                        return true;
                }
                return false;
            }

            /// Hover entry point — the pointer's half of the right-edge strip
            /// picks the card. Deliberately NOT gated on the focused monitor the
            /// way showAudioMetric is: the pointer is physically on THIS screen,
            /// which is the whole point of an edge trigger.
            function showMetric(metric: string): void {
                if (anotherOverlayInteracting())
                    return;

                if (metric === "brightness")
                    brightnessCard.show();
                else
                    audioCard.show();
            }

            function showAudioMetric(metric: string, enabled: bool): void {
                if (!enabled || Hypr.monitorFor(modelData) !== Hypr.focusedMonitor)
                    return;
                if (anotherOverlayInteracting())
                    return;
                if (!audioCard.interacting)
                    audioMetric = metric;
                audioCard.show();
            }

            function show(): void {
                audioCard.show();
                brightnessCard.show();
            }

            function hide(): void {
                audioCard.hide();
                brightnessCard.hide();
            }

            function toggle(): void {
                if (showing)
                    hide();
                else
                    show();
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
                    brightnessCard.show();
                }
            }

            OsdCard {
                id: audioCard

                monitor: win.monitor
                metric: win.audioMetric
                // Volume is never switched off; the microphone rides this card and
                // is gated at the trigger in showAudioMetric instead.
                metricEnabled: true
                offset: -win.metricOffset

                volume: win.volume
                muted: win.muted
                sourceVolume: win.sourceVolume
                sourceMuted: win.sourceMuted
                brightness: win.brightness
            }

            OsdCard {
                id: brightnessCard

                monitor: win.monitor
                metric: "brightness"
                metricEnabled: Config.osd.enableBrightness
                offset: win.metricOffset

                volume: win.volume
                muted: win.muted
                sourceVolume: win.sourceVolume
                sourceMuted: win.sourceMuted
                brightness: win.brightness
            }

            // Union of the two cards' own regions. A single bounding box would
            // also swallow the 28 px gap between the cards and steal clicks from
            // the window underneath it; Combine unions the two rects and leaves
            // the gap click-through.
            //
            // MUST be declared after both cards. `inputRegion` is a readonly
            // alias that never emits a change, so if this list were evaluated
            // before the cards existed it would latch [null, null] and never
            // re-evaluate — the OSD would render but refuse hover and scroll,
            // with nothing logged. QML creates objects in declaration order.
            Region {
                id: maskRegion

                regions: [audioCard.inputRegion, brightnessCard.inputRegion]
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

        // These act on the PAIR — an explicit request to see the OSD means both
        // cards, unlike the metric-specific triggers.
        function toggle(): void { _focusedOverlay()?.toggle(); }
        function show(): void { _focusedOverlay()?.show(); }
        function hide(): void { _focusedOverlay()?.hide(); }

        function isVisible(): bool {
            return Visibilities.osdOverlays.get(Hypr.focusedMonitor)?.showing ?? false;
        }
    }
}
