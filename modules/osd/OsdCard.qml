pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell
import QtQuick

/// One OSD card, parked at a fixed spot on the right edge and owning its own
/// visibility.
///
/// The two cards are INDEPENDENT: each has its own show/hide state and its own
/// auto-hide timer, so raising one never dismisses the other. Trigger volume and
/// then brightness and both stand there until each times out on its own. That is
/// the point — the pair is two destinations you aim at, not one panel that
/// changes what it is showing.
Item {
    id: card

    required property Brightness.Monitor monitor
    /// Which metric this card renders. The audio card swaps between "volume" and
    /// "microphone"; the brightness card is fixed. Because it never crosses into
    /// or out of "brightness", Content's dial Loader never swaps under either
    /// card — each keeps one dial for its whole life.
    required property string metric
    /// Whether this metric is switched on at all. A disabled card never shows,
    /// which is how Config.osd.enableBrightness / enableMicrophone take effect.
    required property bool metricEnabled
    /// Signed distance from the screen's vertical centre. Negative is up.
    required property real offset

    required property real volume
    required property bool muted
    required property real sourceVolume
    required property bool sourceMuted
    required property real brightness

    property bool showing: false

    /// Bound straight to the handler rather than mirrored into a writable
    /// property from onHoveredChanged. A mirror only updates while the handler
    /// keeps emitting: if Qt does not report un-hover when the card is hidden out
    /// from under a resting pointer, the mirror latches true and the card never
    /// auto-hides again. A binding cannot latch.
    readonly property bool hovered: hoverHandler.hovered

    readonly property bool interacting: content.interacting
    /// Exposed so the window can union both cards into one input mask. Sits with
    /// the card because only the card knows where it currently is.
    readonly property alias inputRegion: region

    function show(): void {
        if (!Config.osd.enabled || !metricEnabled)
            return;
        showing = true;
        hideTimer.restart();
    }

    function hide(): void {
        showing = false;
        // An explicit hide (IPC, the showall shortcut) would otherwise leave the
        // timer armed to fire a second, pointless hide up to hideDelay later.
        hideTimer.stop();
    }

    // A metric switched off while its card is on screen should take the card with
    // it, not wait out the timer.
    onMetricEnabledChanged: {
        if (!metricEnabled)
            hide();
    }

    onHoveredChanged: {
        if (hovered)
            hideTimer.stop();
        else if (showing)
            hideTimer.restart();
    }

    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: card.offset

    width: content.implicitWidth
    height: content.implicitHeight

    // opacity drives the Behavior; visible gates layout cost and the input mask
    opacity: showing ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        Anim {}
    }

    // Slide right-to-left on show, left-to-right on hide. Only x is animated —
    // the vertical spot is fixed per card, so y is an anchor offset rather than
    // part of this transform.
    transform: Translate {
        id: slide

        x: card.showing ? 0 : card.width

        Behavior on x {
            Anim {}
        }
    }

    // Click-through when hidden, the card's own rect when visible. Must add the
    // slide because the card is moved by transform, not by its anchors — binding
    // to card.x alone would leave the mask parked at the resting position while
    // the card is still off-screen.
    Region {
        id: region

        intersection: Intersection.Combine

        x: card.visible ? card.x + slide.x : 0
        y: card.visible ? card.y : 0
        width: card.visible ? card.width : 0
        height: card.visible ? card.height : 0
    }

    Content {
        id: content

        anchors.fill: parent

        monitor: card.monitor
        activeMetric: card.metric
        volume: card.volume
        muted: card.muted
        sourceVolume: card.sourceVolume
        sourceMuted: card.sourceMuted
        brightness: card.brightness
        revealed: card.showing
    }

    // Hover detection without consuming wheel/click events. Feeds THIS card's
    // auto-hide only, so resting on one card does not keep the other alive.
    HoverHandler {
        id: hoverHandler
    }

    Timer {
        id: hideTimer

        interval: Config.osd.hideDelay
        onTriggered: {
            if (!card.hovered)
                card.hide();
        }
    }
}
