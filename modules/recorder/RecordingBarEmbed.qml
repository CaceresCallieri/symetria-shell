pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

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

    readonly property var job: {
        if (mode === "audio") return AudioRecorderService.job;
        if (mode === "stt") return SttService.job;
        return null;
    }

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
    readonly property var deliveryModeIcons: RecordingSessionManager.deliveryModeIcons

    function cycleDeliveryMode(): void {
        if (!job || mode !== "stt") return;
        const modes = ["clipboard", "inject", "submit"];
        const idx = modes.indexOf(job.activeDeliveryChoice ?? "clipboard");
        job.setDeliveryChoice(modes[(idx + 1) % modes.length]);
    }

    function formatElapsedTime(seconds: real): string {
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return mins.toString().padStart(2, '0') + ':' + secs.toString().padStart(2, '0');
    }

    // Flat structure: only one child is visible at a time.
    implicitWidth: {
        if (compactRow.visible) return compactRow.implicitWidth;
        if (successIcon.visible) return successIcon.implicitWidth;
        if (errorIcon.visible) return errorIcon.implicitWidth;
        return 0;
    }
    implicitHeight: {
        if (compactRow.visible) return compactRow.implicitHeight;
        if (successIcon.visible) return successIcon.implicitHeight;
        if (errorIcon.visible) return errorIcon.implicitHeight;
        return 0;
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
            text: root.job ? root.formatElapsedTime(root.job.elapsedSeconds) : "00:00"
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

        // Audio level bars
        AudioWaveform {
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: 24

            audioLevel: root.job?.audioLevel ?? 0
            displayState: root.displayState
            containerHeight: 24
            active: root.isRecordingPhase
        }

        // Separator before trailing icon (visible when icon is visible)
        StyledText {
            visible: audioIcon.visible || deliveryModeBtn.visible
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

        // STT mode: delivery mode icon (ask mode only)
        PillButton {
            id: deliveryModeBtn

            visible: root.isAskMode
            icon: root.deliveryModeIcons[root.job?.activeDeliveryChoice ?? "clipboard"] ?? "content_copy"
            onClicked: root.cycleDeliveryMode()
        }
    }

    // ── Compact success indicator ───────────────────────────
    MaterialIcon {
        id: successIcon

        anchors.centerIn: parent
        visible: root.displayState === "success"
        text: root.mode === "audio" ? "audio_file" : "check_circle"
        color: Colours.palette.m3confirm
        font.pointSize: Appearance.font.size.large
        opacity: visible ? 1 : 0

        Behavior on opacity { Anim {} }
    }

    // ── Compact error indicator ─────────────────────────────
    MaterialIcon {
        id: errorIcon

        anchors.centerIn: parent
        visible: root.displayState === "error"
        text: "error"
        color: Colours.palette.m3error
        font.pointSize: Appearance.font.size.large
        opacity: visible ? 1 : 0

        Behavior on opacity { Anim {} }
    }
}
