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
            ///
            /// Clamped to half a card so the pair can never overlap: below a
            /// triggerHeight of about 264 the derived offset is smaller than the
            /// cards are tall, and they would collide on screen and merge their
            /// input masks. Past that floor the card simply stops being centred in
            /// its (now smaller) zone, which is the milder failure.
            readonly property real metricOffset: Math.max(Config.osd.triggerHeight / 4, audioCard.height / 2)

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

                if (metric === "brightness") {
                    brightnessCard.show();
                    return;
                }

                // Hovering the audio zone asks for VOLUME, so say so. Without this
                // the card would keep showing whatever audio metric last moved —
                // reach for the volume spot after touching the microphone and you
                // would get the microphone, which is not what the zone advertises.
                if (!audioCard.interacting)
                    audioMetric = metric;
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
                // Falls back to volume if the microphone is switched off while it
                // is the metric on show: the trigger in showAudioMetric gates new
                // microphone events, but the card would otherwise sit there
                // rendering a metric the user has turned off.
                metric: win.audioMetric === "microphone" && !Config.osd.enableMicrophone ? "volume" : win.audioMetric
                // Volume itself is never switched off, so this card is always live.
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
            // `inputRegion` is a readonly alias, so this list is evaluated once
            // and never again — which is correct: it captures two objects that
            // live as long as the cards do, and each keeps its own live bindings
            // for x/y/width/height. Declaration order is irrelevant here; QML
            // registers every id in the component before evaluating any binding,
            // as Wrapper.qml's mask does when it references a Variants declared
            // below it.
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
