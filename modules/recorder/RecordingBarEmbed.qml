pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

// The bar's recordingCenterContainer is transparent — there is no surrounding
// claymorphism pill to embed against. We add our own PillCard backdrop here
// so the timer/waveform/delivery cluster reads with sufficient contrast over
// arbitrary wallpapers. Note: the container no longer clips its children
// (clip was removed when the scale-overshoot animation replaced the horizontal
// clip-reveal), so PillCard's full claymorphism — including the outer halo —
// is visible.

/// Compact recording indicator for the bar center (merge mode).
///
/// Mode-aware: shows audio recording (mic icon) or STT (delivery mode
/// icon) depending on RecordingSessionManager.activeMode. Falls back
/// to the drawer when merge mode is off.
///
/// Layout: [MM:SS] · [waveform bars] · [mode icon]
/// On success/error: brief icon indicator with auto-dismiss.
Item {
    id: root

    readonly property string mode: RecordingSessionManager.activeMode

    // intentional var: polymorphic job (SttJob | AudioRecorderJob | null)
    readonly property var job: RecordingSessionManager.currentJob

    // Coalesce internal states to user-visible states
    readonly property string displayState: {
        if (!job) return "idle";
        const s = job.state;
        if (mode === "audio" && s === "saving") return "processing";
        if (mode === "stt" && (s === "transcribed" || s === "delivering")) return "processing";
        return s;
    }

    readonly property bool isRecordingPhase: displayState === "recording"
        || displayState === "paused"
        || displayState === "processing"

    // STT delivery mode
    readonly property bool isAskMode: mode === "stt" && SttService.isAskMode

    // Live streaming partial transcript (STT streaming mode). "" otherwise.
    //
    // CONTRACT — the streaming partial preview has TWO surfaces: this bar embed
    // (merge mode, the primary one in daily use) and the drawer
    // (modules/recorder/Content.qml). If you add or change streaming-partial
    // behaviour on one surface, mirror it on the other — otherwise the preview
    // silently vanishes for whichever surface the user is actually in. The
    // bar-embed treatment is intentionally different (grow-with-cap + ElideLeft
    // inside the pill, no waveform) vs the drawer (wrapped text block).
    readonly property string partialTranscript: mode === "stt" ? (job?.partialTranscript ?? "") : ""
    readonly property bool showStreamingText: mode === "stt"
        && SttService.streamingActive
        && partialTranscript !== ""
        && isRecordingPhase
    // Max pill text width before older words scroll off the left (ElideLeft).
    readonly property real partialMaxWidth: 414

    // Padding around the visible child, sized so the PillCard frame has
    // breathing room above/below the timer + waveform without making the
    // bar embed feel chunky. Asymmetric (more horizontal than vertical)
    // matches the natural pill shape we get with rounding.full.
    readonly property real cardPadX: Appearance.padding.large
    readonly property real cardPadY: Appearance.padding.smaller

    // Flat structure: only one child is visible at a time. Add card padding
    // to whichever child is active so the PillCard backdrop sits a comfortable
    // margin away from the content.
    implicitWidth: {
        if (compactRow.visible) return compactRow.implicitWidth + cardPadX * 2;
        if (successIcon.visible) return successIcon.implicitWidth + cardPadX * 2;
        if (errorIcon.visible) return errorIcon.implicitWidth + cardPadX * 2;
        return 0;
    }
    implicitHeight: {
        if (compactRow.visible) return compactRow.implicitHeight + cardPadY * 2;
        if (successIcon.visible) return successIcon.implicitHeight + cardPadY * 2;
        if (errorIcon.visible) return errorIcon.implicitHeight + cardPadY * 2;
        return 0;
    }

    // Claymorphism backdrop. Capsule rounding (rounding.full = 1000) so the
    // embed reads as a true pill against the transparent bar surface. Declared
    // before the content children so it paints behind them.
    PillCard {
        anchors.fill: parent
        radius: Appearance.rounding.full
        // Hide when there's nothing to show — implicitWidth collapses to 0
        // during idle/closed states, and an empty card would briefly flash.
        visible: parent.implicitWidth > 0

        // Shadow tail trimmed to match PillSurface (top-bar info pills). The
        // default PillCard tail (offset 4, blur 14 → ~18px past the body) was
        // bleeding 2-3px more shadow past the bar's bottom edge than the
        // neighboring claymorphism pills, producing a visibly larger downward
        // "bump" under the STT pill specifically. Floating PillCard consumers
        // (popouts, clipboard cards) keep the full softer shadow via the
        // type's defaults — this trim is local to the bar-embed context.
        darkShadowOffsetY: 3
        darkShadowBlur: 12
        darkShadowAlpha: 0.40
    }

    // ── Compact row: [timer] · [waveform] · [mode icon] ─────
    RowLayout {
        id: compactRow

        visible: root.isRecordingPhase
        opacity: visible ? 1 : 0
        anchors.centerIn: parent
        spacing: Appearance.spacing.small

        Behavior on opacity { Anim {} }

        // Elapsed timer
        StyledText {
            opacity: root.displayState === "paused" ? 0.55 : 1.0
            text: root.job ? RecordingSessionManager.formatElapsedTime(root.job.elapsedSeconds) : "00:00"
            font.pointSize: Appearance.font.size.small * 0.88
            font.family: Appearance.font.family.mono
            color: Colours.palette.m3outline

            Behavior on opacity { Anim {} }
        }

        StyledText {
            text: "\u00b7"
            font.pointSize: Appearance.font.size.small
            color: Colours.palette.m3outlineVariant
        }

        // Audio level bars. Hidden in streaming mode — the live text replaces
        // the waveform inside the pill (per the embed treatment).
        AudioWaveform {
            visible: !root.showStreamingText
            Layout.preferredWidth: visible ? implicitWidth : 0
            Layout.preferredHeight: 24

            audioLevel: root.job?.audioLevel ?? 0
            displayState: root.displayState
            containerHeight: 24
            active: root.isRecordingPhase
        }

        // STT streaming: live partial transcript inside the pill. The pill
        // grows with the text up to partialMaxWidth; past that, ElideLeft keeps
        // the NEWEST words visible while older ones scroll off the left.
        StyledText {
            visible: root.showStreamingText
            Layout.maximumWidth: root.partialMaxWidth
            text: root.partialTranscript
            elide: Text.ElideLeft
            maximumLineCount: 1
            font.pointSize: Appearance.font.size.small
            color: Colours.palette.m3onSurface
        }

        // Separator before trailing icon (visible when icon is visible)
        StyledText {
            visible: audioIcon.visible || deliveryModeBtn.visible || vocabBadge.visible
            text: "\u00b7"
            font.pointSize: Appearance.font.size.small
            color: Colours.palette.m3outlineVariant
        }

        // Audio mode: mic icon
        MaterialIcon {
            id: audioIcon

            visible: root.mode === "audio"
            text: "mic"
            color: root.displayState === "recording" ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
            font.pointSize: Appearance.font.size.small
        }

        // STT mode: delivery mode icon (ask mode only). Raised Tonal
        // IconButton matches the drawer's modeBtn so the same control reads
        // identically regardless of merge-mode surface.
        //
        // Icon size dropped one step from MaterialIcon's default (larger=15)
        // to normal=13. Default is visibly taller than the date/system/tray
        // pills next to it in the bar; small=11 reads as undersized. Padding
        // stays at the IconButton.Tonal default (smaller=7) so the affordance
        // doesn't feel cramped.
        IconButton {
            id: deliveryModeBtn

            visible: root.isAskMode
            icon: RecordingSessionManager.deliveryModeIcons[root.job?.activeDeliveryChoice ?? "clipboard"] ?? "content_copy"
            type: IconButton.Tonal
            toggle: false
            raised: true
            font.pointSize: Appearance.font.size.normal
            onClicked: RecordingSessionManager.cycleDeliveryMode()
        }

        // Inline vocab-hint count, placed after the delivery pill.
        // See Content.qml for the matching drawer placement.
        VocabHintBadge {
            id: vocabBadge
            Layout.alignment: Qt.AlignTop
        }
    }

    // ── Compact success indicator ───────────────────────────
    // Scales 0 → 1 with the expressive overshoot curve when the success
    // state is entered, matching the bar embed's open/close motion vocabulary
    // and the drawer's SttSuccessCard pop-in. The visible guard keeps the
    // icon painted while scale shrinks back to 0 so the exit animation has
    // something to render — visible flips false only after scale reaches 0.
    MaterialIcon {
        id: successIcon

        readonly property bool _show: root.displayState === "success"

        anchors.centerIn: parent
        visible: _show || scale > 0.001
        text: root.mode === "audio" ? "audio_file" : "check_circle"
        // M3 "on surface" foreground role — near-white in dark mode, theme-
        // adaptive in light mode. Replaces the prior m3confirm (green) so the
        // success status reads as crisp white against the claymorphism capsule
        // rather than a green-on-tinted-green blend. The submit button (also
        // ✓ check, hover row) keeps m3confirm because it's an action-intent
        // color, not a status color — different UI role.
        color: Colours.palette.m3onSurface
        font.pointSize: Appearance.font.size.large
        transformOrigin: Item.Center
        scale: _show ? 1.0 : 0.0

        Behavior on scale {
            NumberAnimation {
                duration: Appearance.anim.durations.expressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
            }
        }
    }

    // ── Compact error indicator ─────────────────────────────
    MaterialIcon {
        id: errorIcon

        readonly property bool _show: root.displayState === "error"

        anchors.centerIn: parent
        visible: _show || scale > 0.001
        text: "error"
        color: Colours.palette.m3error
        font.pointSize: Appearance.font.size.large
        transformOrigin: Item.Center
        scale: _show ? 1.0 : 0.0

        Behavior on scale {
            NumberAnimation {
                duration: Appearance.anim.durations.expressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
            }
        }
    }
}
