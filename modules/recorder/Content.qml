pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
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
        if (mode === "audio" && s === "saving")
            return "processing";
        if (mode === "stt" && (s === "transcribed" || s === "delivering"))
            return "processing";
        return s;
    }

    readonly property real audioLevel: job?.audioLevel ?? 0
    readonly property real elapsedSeconds: job?.elapsedSeconds ?? 0

    // Live partial transcript (STT streaming mode). "" for non-STT jobs.
    readonly property string partialTranscript: mode === "stt" ? (job?.partialTranscript ?? "") : ""

    // ── STT-specific property aliases ──────────────────────────────

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
                // M3 "on surface" foreground for both modes — collapses the prior
                // split (audio: m3confirm green / STT: m3primary accent) into a
                // unified white success indicator that reads consistently against
                // the claymorphism card. Status icons get the neutral on-surface
                // role; only action-intent buttons (the hover-row submit ✓) keep
                // their semantic color (m3confirm).
                iconColor: Colours.palette.m3onSurface
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

    Item {
        id: container

        anchors.top: parent.top
        anchors.topMargin: Appearance.padding.large
        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth: content.implicitWidth + Appearance.padding.large * 2
        implicitHeight: content.implicitHeight + Appearance.padding.large * 2

        // Claymorphism frame matching the clipboard popout's stacked cards
        // and the calendar popout's panelMode sections. The recorder drawer
        // previously sat on a transparent rect (only the drawer's outer pane
        // provided visual containment); the card gives the timer/waveform/
        // action-row cluster its own held surface so it reads as a coherent
        // pill rather than text floating in the void.
        PillCard {
            anchors.fill: parent
        }

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

                        Behavior on opacity {
                            Anim {}
                        }
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
                        visible: audioModeIcon.visible || modeBtn.visible || vocabBadge.visible
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
                    // Raised Tonal IconButton matches the calendar popout's
                    // chevrons and the utilities popup's pill aesthetic now
                    // that the recorder content sits inside its own PillCard.
                    // Plain PillButton would read as a flat pill-on-pill.
                    IconButton {
                        id: modeBtn

                        visible: root.mode === "stt"
                        icon: RecordingSessionManager.deliveryModeIcons[root.serviceDeliveryChoice] ?? "content_copy"
                        type: IconButton.Tonal
                        toggle: false
                        raised: true
                        onClicked: RecordingSessionManager.cycleDeliveryMode()
                    }

                    // Inline vocab-hint count sibling — placed after the
                    // delivery pill. Previously tried as an anchored child
                    // floating above-right of the pill; that works in the
                    // drawer but gets clipped in the bar embed because
                    // recordingCenterContainer in Bar.qml uses clip: true
                    // (needed for the horizontal reveal animation) and the
                    // bar's layer-shell surface caps the vertical extent.
                    // Keeping the two surfaces consistent is more valuable
                    // than optimizing the drawer placement separately.
                    VocabHintBadge {
                        id: vocabBadge
                        Layout.alignment: Qt.AlignTop
                    }
                }
            }

            // ── Streaming live partial preview (STT streaming mode) ───
            // Shows what the streaming backend is hearing in real time so the
            // user can re-dictate mishearings on the fly. Preview only — the
            // delivered text still comes from the batch path.
            //
            // CONTRACT — this is ONE of TWO partial-preview surfaces; the other
            // is the bar embed (RecordingBarEmbed.qml), which is the primary one
            // in daily use (merge mode). Keep both in sync: a streaming-partial
            // change here must be mirrored there, or the preview disappears for
            // whichever surface the user is in. The treatments differ on purpose
            // (wrapped block here; grow-with-cap + ElideLeft pill there).
            FadeTransition {
                Layout.alignment: Qt.AlignHCenter
                show: root.mode === "stt" && root.partialTranscript !== "" && (root.displayState === "recording" || root.displayState === "processing")

                StyledText {
                    width: 320
                    text: root.partialTranscript
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    font.pointSize: Appearance.font.size.small
                    color: Colours.palette.m3onSurfaceVariant
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
                show: root.hovered && (root.displayState === "recording" || root.displayState === "paused")

                RowLayout {
                    spacing: Appearance.spacing.normal

                    // Hover-row actions: raised Tonal IconButtons. Override
                    // inactiveOnColour to map the prior PillButton.iconColor
                    // semantics (pause→primary when paused, cancel→error,
                    // submit→confirm) onto IconButton's coloring API.
                    // triggerPress() was ported into IconButton specifically
                    // for these consumers — IPC-driven pause/cancel/stop
                    // events still squeeze the matching button.
                    IconButton {
                        id: pauseBtn
                        icon: root.displayState === "paused" ? "play_arrow" : "pause"
                        type: IconButton.Tonal
                        toggle: false
                        raised: true
                        inactiveOnColour: root.displayState === "paused" ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        onClicked: {
                            if (root.mode === "stt")
                                root.job?.recording ? root.job.pause() : root.job.resume();
                            else
                                AudioRecorderService.pause();
                        }
                    }

                    // Restart (STT only)
                    IconButton {
                        id: restartBtn
                        visible: root.mode === "stt"
                        icon: "restart_alt"
                        type: IconButton.Tonal
                        toggle: false
                        raised: true
                        onClicked: SttService.restart()
                    }

                    IconButton {
                        id: cancelBtn
                        icon: "close"
                        type: IconButton.Tonal
                        toggle: false
                        raised: true
                        inactiveOnColour: Colours.palette.m3error
                        onClicked: root.job?.cancel()
                    }

                    IconButton {
                        id: submitBtn
                        icon: "check"
                        type: IconButton.Tonal
                        toggle: false
                        raised: true
                        inactiveOnColour: Colours.palette.m3confirm
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
                show: root.mode === "stt" && SttService.sessionVocabHints.length > 0 && (root.displayState === "recording" || root.displayState === "paused")

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
                    if (sessionId !== "" && sessionId !== root.job?.sessionId)
                        return;
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
