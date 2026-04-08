pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

/// Unified content UI for the recorder drawer card.
///
/// Shared base handles: container, hover debounce, compact row (timer +
/// waveform), height transitions. Mode-specific sections (trailing icon,
/// hover buttons, success/error, extras) are selected based on
/// RecordingSessionManager.activeMode.
///
/// Compact horizontal layout:
/// - Default: [MM:SS] · [waveform] · [mode icon]
/// - Hover: action buttons (pause, [restart], cancel, stop/submit)
///
/// Terminal states (error, success) replace the compact row.
Item {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities

    // ── Mode + job resolution ──────────────────────────────────────

    readonly property string mode: RecordingSessionManager.activeMode

    // intentional var: polymorphic job (SttJob | AudioRecorderJob | null)
    readonly property var job: RecordingSessionManager.currentJob

    // ── State mapping (mode-aware) ─────────────────────────────────

    readonly property string displayState: {
        const s = job?.state ?? "idle";
        if (mode === "audio" && s === "saving") return "processing";
        if (mode === "stt" && (s === "transcribed" || s === "delivering")) return "processing";
        return s;
    }

    readonly property real audioLevel: job?.audioLevel ?? 0
    readonly property real elapsedSeconds: job?.elapsedSeconds ?? 0

    // ── STT-specific property aliases ──────────────────────────────

    readonly property bool serviceIsAskMode: mode === "stt" && SttService.isAskMode
    readonly property string serviceDeliveryChoice: job?.activeDeliveryChoice ?? "clipboard"
    readonly property string serviceInjectionPath: job?.injectionPath ?? ""
    readonly property bool serviceInjectionDowngraded: job?.injectionDowngraded ?? false
    readonly property bool serviceInjectionSubmitted: job?.injectionSubmitted ?? false
    readonly property bool serviceAutoRetrying: job?.autoRetrying ?? false
    readonly property string serviceErrorRaw: job?.errorRaw ?? ""
    readonly property string serviceErrorSource: job?.errorSource ?? ""

    // ── Shared properties ──────────────────────────────────────────

    property bool hovered: false

    readonly property int barCount: 16
    readonly property int audioBarContainerHeight: 24

    Timer {
        id: hoverDebounce
        interval: 150
        onTriggered: root.hovered = false
    }

    // ── State configuration map (mode-aware icon colors) ───────────

    readonly property var stateMap: ({
        "recording": {
            icon: "mic",
            iconColor: root.mode === "audio" ? Colours.palette.m3error : Colours.palette.m3primary
        },
        "paused": {
            icon: "pause",
            iconColor: Colours.palette.m3tertiary
        },
        "processing": {
            icon: "hourglass_top",
            iconColor: Colours.palette.m3secondary
        },
        "error": {
            icon: "error",
            iconColor: Colours.palette.m3error
        },
        "success": {
            icon: root.mode === "audio" ? "audio_file" : "check_circle",
            iconColor: root.mode === "audio" ? Colours.palette.m3confirm : Colours.palette.m3primary
        },
        "idle": {
            icon: "mic",
            iconColor: Colours.palette.m3onSurface
        }
    })

    readonly property var stateConfig: stateMap[root.displayState] ?? stateMap["idle"]

    // ── Terminal state components (extracted to dedicated files) ───

    Component {
        id: audioSuccessComponent
        AudioSuccessCard {
            containerWidth: compactRow.implicitWidth
            containerHeight: compactRow.implicitHeight
            iconColor: root.stateConfig.iconColor
        }
    }

    Component {
        id: sttSuccessComponent
        SttSuccessCard {
            containerWidth: compactRow.implicitWidth
            containerHeight: compactRow.implicitHeight
            iconColor: root.stateConfig.iconColor
            injectionDowngraded: root.serviceInjectionDowngraded
            injectionPath: root.serviceInjectionPath
            injectionSubmitted: root.serviceInjectionSubmitted
            isAskMode: root.serviceIsAskMode
            modeBtnX: modeBtn.x
            modeBtnWidth: modeBtn.width
        }
    }

    Component {
        id: audioErrorComponent
        AudioErrorCard {
            stateIcon: root.stateConfig.icon
            stateIconColor: root.stateConfig.iconColor
            job: root.job
            displayState: root.displayState
        }
    }

    Component {
        id: sttErrorComponent
        SttErrorCard {
            stateIcon: root.stateConfig.icon
            stateIconColor: root.stateConfig.iconColor
            job: root.job
            displayState: root.displayState
            errorSource: root.serviceErrorSource
            errorRaw: root.serviceErrorRaw
        }
    }

    // ── Layout ─────────────────────────────────────────────────────

    implicitWidth: container.implicitWidth
    implicitHeight: container.implicitHeight + Appearance.padding.large

    StyledRect {
        id: container

        anchors.top: parent.top
        anchors.topMargin: Appearance.padding.large
        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth: content.implicitWidth + Appearance.padding.large * 2
        implicitHeight: content.implicitHeight + Appearance.padding.large * 2

        radius: Appearance.rounding.normal
        color: "transparent"

        HoverHandler {
            id: cardHover

            onHoveredChanged: {
                if (hovered) {
                    hoverDebounce.stop();
                    root.hovered = true;
                } else {
                    hoverDebounce.restart();
                }
            }
        }

        ColumnLayout {
            id: content

            anchors.centerIn: parent
            spacing: Appearance.spacing.small

            // ── Compact row: [timer] · [waveform] · [mode icon] ───
            FadeTransition {
                Layout.alignment: Qt.AlignHCenter
                show: root.displayState === "recording" || root.displayState === "paused" || root.displayState === "processing"

                RowLayout {
                    id: compactRow

                    spacing: Appearance.spacing.small

                    // Elapsed timer
                    StyledText {
                        opacity: root.displayState === "paused" ? 0.55 : 1.0
                        text: RecordingSessionManager.formatElapsedTime(root.elapsedSeconds)
                        font.pointSize: Appearance.font.size.small * 0.88
                        font.family: Appearance.font.family.mono
                        color: Colours.palette.m3outline

                        Behavior on opacity { Anim {} }
                    }

                    StyledText {
                        text: "·"
                        font.pointSize: Appearance.font.size.small
                        color: Colours.palette.m3outlineVariant
                    }

                    // Audio level waveform
                    AudioWaveform {
                        Layout.preferredWidth: implicitWidth
                        Layout.preferredHeight: root.audioBarContainerHeight

                        audioLevel: root.audioLevel
                        displayState: root.displayState
                        barCount: root.barCount
                        containerHeight: root.audioBarContainerHeight
                        active: root.visibilities.recorder
                    }

                    // Separator before trailing icon
                    StyledText {
                        visible: audioModeIcon.visible || modeBtn.visible
                        text: "·"
                        font.pointSize: Appearance.font.size.small
                        color: Colours.palette.m3outlineVariant
                    }

                    // ── Audio mode: static state icon ─────────────
                    MaterialIcon {
                        id: audioModeIcon

                        visible: root.mode === "audio"
                        text: root.stateConfig.icon
                        color: root.stateConfig.iconColor
                        font.pointSize: Appearance.font.size.small
                    }

                    // ── STT mode: delivery mode button ────────────
                    PillButton {
                        id: modeBtn

                        visible: root.mode === "stt" && root.serviceIsAskMode
                        icon: RecordingSessionManager.deliveryModeIcons[root.serviceDeliveryChoice] ?? "content_copy"
                        onClicked: RecordingSessionManager.cycleDeliveryMode()
                    }
                }
            }

            // ── Auto-retry indicator (STT only) ───────────────────
            FadeTransition {
                Layout.alignment: Qt.AlignHCenter
                show: root.mode === "stt" && root.serviceAutoRetrying

                StyledText {
                    text: "retrying…"
                    font.pointSize: Appearance.font.size.small
                    font.italic: true
                    color: Colours.palette.m3outline
                }
            }

            // ── Hover-expanded action buttons ─────────────────────
            FadeTransition {
                Layout.alignment: Qt.AlignHCenter
                show: root.hovered
                    && (root.displayState === "recording" || root.displayState === "paused")

                RowLayout {
                    spacing: Appearance.spacing.normal

                    PillButton {
                        id: pauseBtn
                        icon: root.displayState === "paused" ? "play_arrow" : "pause"
                        iconColor: root.displayState === "paused" ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        onClicked: {
                            if (root.mode === "stt")
                                root.job?.recording ? root.job.pause() : root.job.resume();
                            else
                                AudioRecorderService.pause();
                        }
                    }

                    // Restart (STT only)
                    PillButton {
                        id: restartBtn
                        visible: root.mode === "stt"
                        icon: "restart_alt"
                        onClicked: SttService.restart()
                    }

                    PillButton {
                        id: cancelBtn
                        icon: "close"
                        iconColor: Colours.palette.m3error
                        onClicked: root.job?.cancel()
                    }

                    PillButton {
                        id: submitBtn
                        icon: "check"
                        iconColor: Colours.palette.m3confirm
                        onClicked: {
                            if (root.mode === "stt")
                                root.job?.stop();
                            else
                                AudioRecorderService.stop();
                        }
                    }
                }
            }

            // ── Vocabulary hint chips (STT only) ──────────────────
            FadeTransition {
                Layout.alignment: Qt.AlignHCenter
                show: root.mode === "stt"
                    && SttService.sessionVocabHints.length > 0
                    && (root.displayState === "recording" || root.displayState === "paused")

                VocabHintChips {}
            }

            // ── Audio IPC action feedback ─────────────────────────
            Connections {
                target: root.mode === "audio" ? AudioRecorderService : null

                function onActionTriggered(action: string): void {
                    switch (action) {
                        case "pause":
                        case "resume":
                            pauseBtn.triggerPress();
                            break;
                        case "cancel":
                            if (root.displayState !== "error")
                                cancelBtn.triggerPress();
                            break;
                        case "stop":
                            submitBtn.triggerPress();
                            break;
                    }
                }
            }

            // ── STT IPC action feedback ───────────────────────────
            Connections {
                target: root.mode === "stt" ? SttService : null

                function onActionTriggered(sessionId: string, action: string): void {
                    if (sessionId !== "" && sessionId !== root.job?.sessionId) return;
                    switch (action) {
                        case "pause":
                        case "resume":
                            pauseBtn.triggerPress();
                            break;
                        case "restart":
                            restartBtn.triggerPress();
                            break;
                        case "cancel":
                            if (root.displayState !== "error")
                                cancelBtn.triggerPress();
                            break;
                        case "stop":
                            submitBtn.triggerPress();
                            break;
                        case "mode-clipboard":
                        case "mode-inject":
                        case "mode-submit":
                            modeBtn.triggerPress();
                            break;
                    }
                }
            }

            // ── Terminal state (success/error) ────────────────────
            Loader {
                Layout.alignment: Qt.AlignHCenter

                sourceComponent: {
                    if (root.displayState === "success")
                        return root.mode === "stt" ? sttSuccessComponent : audioSuccessComponent;
                    if (root.displayState === "error")
                        return root.mode === "stt" ? sttErrorComponent : audioErrorComponent;
                    return null;
                }
            }
        }
    }
}
