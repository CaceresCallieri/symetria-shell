pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import qs.modules.stt as SttModule
import QtQuick
import QtQuick.Layouts

/// Compact audio recording indicator for the bar center.
///
/// Shown when AgentService.mergeActive is true (workspaces moved to bottom
/// bar, leaving center empty). Falls back to the drawer when merge is off.
///
/// Layout: [MM:SS] · [waveform bars] · [mic icon]
/// On success/error: brief icon indicator with auto-dismiss.
Item {
    id: root

    readonly property AudioRecorderJob job: AudioRecorderService.job

    // Coalesce internal states to user-visible states
    readonly property string displayState: {
        if (!job) return "idle";
        const s = job.state;
        if (s === "saving") return "processing";
        return s;
    }

    readonly property bool isRecordingPhase: displayState === "recording"
        || displayState === "paused"
        || displayState === "processing"

    function formatElapsedTime(seconds: real): string {
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return mins.toString().padStart(2, '0') + ':' + secs.toString().padStart(2, '0');
    }

    // Flat structure: only one child is visible at a time.
    // Compute implicit size directly from the active child.
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

    // ── Compact row: [timer] · [waveform] · [mic icon] ─────
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

        // Separator
        StyledText {
            text: "\u00b7"
            font.pointSize: Appearance.font.size.small
            color: Colours.palette.m3outlineVariant
        }

        // Audio level bars
        SttModule.SttWaveform {
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: 24

            audioLevel: root.job?.audioLevel ?? 0
            sttState: root.displayState
            containerHeight: 24
            active: root.isRecordingPhase
        }

        // Separator
        StyledText {
            text: "\u00b7"
            font.pointSize: Appearance.font.size.small
            color: Colours.palette.m3outlineVariant
        }

        // Mic icon — indicates audio recording mode
        MaterialIcon {
            text: "mic"
            color: root.displayState === "recording" ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
            font.pointSize: Appearance.font.size.small
        }
    }

    // ── Compact success indicator ───────────────────────────
    MaterialIcon {
        id: successIcon

        anchors.centerIn: parent
        visible: root.displayState === "success"
        text: "audio_file"
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
