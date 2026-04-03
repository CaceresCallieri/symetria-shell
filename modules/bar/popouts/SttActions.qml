pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import qs.modules.stt as SttModule
import QtQuick
import QtQuick.Layouts

/// Popout panel for STT bar embed hover interaction.
///
/// Shows action buttons (pause, restart, cancel, submit) and
/// vocabulary hint management (chips + text input). Drops down
/// from the bar when hovering over the STT center embed.
ColumnLayout {
    id: root

    readonly property SttService.SttJob job: {
        const jobs = SttService.jobs;
        return jobs.length > 0 ? jobs[jobs.length - 1] : null;
    }

    spacing: Appearance.spacing.normal
    implicitWidth: 280

    // ── Action buttons (hover only, hidden during Alt+W vocab mode) ──
    FadeTransition {
        Layout.alignment: Qt.AlignHCenter
        show: root.job !== null
            && (root.job.state === "recording" || root.job.state === "paused")
            && !SttService.vocabHintsVisible

        RowLayout {
            spacing: Appearance.spacing.normal

            PillButton {
                id: pauseBtn

                icon: root.job?.recording ? "pause" : "play_arrow"
                iconColor: root.job?.recording ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3primary
                onClicked: {
                    if (!root.job) return;
                    root.job.recording ? root.job.pause() : root.job.resume();
                }
            }

            PillButton {
                id: restartBtn

                icon: "restart_alt"
                onClicked: SttService.restart()
            }

            PillButton {
                id: cancelBtn

                icon: "close"
                iconColor: Colours.palette.m3error
                onClicked: {
                    if (root.job) root.job.cancel();
                }
            }

            PillButton {
                id: submitBtn

                icon: "check"
                iconColor: Colours.palette.m3confirm
                onClicked: {
                    if (root.job) root.job.stop();
                }
            }
        }
    }

    // ── Vocabulary hint chips ───────────────────────────────────
    FadeTransition {
        Layout.alignment: Qt.AlignHCenter
        show: SttService.sessionVocabHints.length > 0
            && root.job !== null
            && (root.job.state === "recording" || root.job.state === "paused")

        Row {
            spacing: Appearance.spacing.smaller

            Repeater {
                model: SttService.sessionVocabHints

                StyledRect {
                    id: hintChipBg

                    required property string modelData
                    required property int index

                    implicitWidth: Math.max(chipText.implicitWidth, chipDeleteIcon.implicitWidth) + Appearance.padding.large * 2
                    implicitHeight: chipText.implicitHeight + Appearance.padding.small * 2

                    radius: Appearance.rounding.full
                    color: Colours.pillStyle(
                        Colours.palette.m3surfaceContainerHigh,
                        Colours.glass.subtle
                    ).background

                    MouseArea {
                        id: chipDeleteArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: SttService.removeSessionHint(index)
                    }

                    StyledText {
                        id: chipText

                        anchors.centerIn: parent
                        visible: !chipDeleteArea.containsMouse
                        text: modelData
                        color: Colours.palette.m3onSurface
                        font.pointSize: Appearance.font.size.small
                    }

                    MaterialIcon {
                        id: chipDeleteIcon

                        anchors.centerIn: parent
                        visible: chipDeleteArea.containsMouse
                        text: "delete"
                        color: Colours.palette.m3error
                        font.pointSize: Appearance.font.size.small
                    }
                }
            }
        }
    }

    // ── Vocabulary hints text input ─────────────────────────────
    FadeTransition {
        Layout.alignment: Qt.AlignHCenter
        show: SttService.vocabHintsVisible && SttService.active

        SttModule.VocabularyHints {}
    }

    // ── IPC action visual feedback ─────────────────────────────
    Connections {
        target: SttService

        function onActionTriggered(sessionId: string, action: string): void {
            if (!root.job) return;
            if (sessionId !== "" && sessionId !== root.job.sessionId) return;

            switch (action) {
                case "pause":
                case "resume":
                    pauseBtn.triggerPress();
                    break;
                case "restart":
                    restartBtn.triggerPress();
                    break;
                case "cancel":
                    cancelBtn.triggerPress();
                    break;
                case "stop":
                    submitBtn.triggerPress();
                    break;
            }
        }
    }
}
