pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

/// Content UI for a single SttJob in the speech-to-text drawer.
///
/// Compact horizontal layout:
/// - Collapsed (default): [MM:SS] · [waveform] · [mode icon]
/// - Expanded (on hover): action buttons appear below
///
/// Terminal states (error, success) replace the compact row entirely.
Item {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities
    required property SttJob job

    /// When false, container size changes are instant (no animation).
    /// Wrapper sets this to true after its clip-reveal animation completes,
    /// so that subsequent state transitions animate smoothly.
    property bool enableHeightTransition: false

    // Hover state with debounce to prevent flicker at container edge
    property bool hovered: false

    Timer {
        id: hoverDebounce
        interval: 150
        onTriggered: root.hovered = false
    }

    // Aliases so all existing internal references keep working without rename.
    // "transcribed" and "delivering" display as "processing" to the user.
    readonly property string serviceState: {
        const s = job.state;
        if (s === "transcribed" || s === "delivering") return "processing";
        return s;
    }
    readonly property real serviceAudioLevel: job.audioLevel
    readonly property real serviceElapsedSeconds: job.elapsedSeconds
    readonly property string serviceErrorDetail: job.errorDetail
    readonly property string serviceErrorHint: job.errorHint
    readonly property string serviceErrorRaw: job.errorRaw
    readonly property string serviceErrorSource: job.errorSource
    readonly property bool serviceIsAskMode: SttService.isAskMode
    readonly property string serviceDeliveryChoice: job.activeDeliveryChoice
    readonly property string serviceInjectionPath: job.injectionPath
    readonly property bool serviceInjectionDowngraded: job.injectionDowngraded
    readonly property bool serviceInjectionSubmitted: job.injectionSubmitted
    readonly property bool serviceAutoRetrying: job.autoRetrying

    // Number of audio visualizer bars (compact layout)
    readonly property int barCount: 16
    // Height of audio level bar container
    readonly property int audioBarContainerHeight: 24

    // Delivery mode cycling (replaces 3-button radio group)
    readonly property var deliveryModes: ["clipboard", "inject", "submit"]
    readonly property var deliveryModeIcons: ({
        "clipboard": "content_copy",
        "inject": "input",
        "submit": "send"
    })

    function cycleDeliveryMode(): void {
        const idx = deliveryModes.indexOf(serviceDeliveryChoice);
        const next = deliveryModes[(idx + 1) % deliveryModes.length];
        root.job.setDeliveryChoice(next);
    }

    function formatElapsedTime(seconds: real): string {
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return mins.toString().padStart(2, '0') + ':' + secs.toString().padStart(2, '0');
    }

    // State configuration map
    readonly property var stateMap: ({
        "recording": {
            icon: "mic",
            iconColor: Colours.palette.m3primary
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
            iconColor: Colours.palette.m3primary
        },
        "idle": {
            icon: "mic",
            iconColor: Colours.palette.m3onSurface
        }
    })

    // "idle" is the safe fallback — jobs are added to _jobs only after state is "recording",
    // so this branch is unreachable in normal operation but guards against unknown states.
    readonly property var stateConfig: stateMap[root.serviceState] ?? stateMap["idle"]

    // Success state: the delivery mode icon slides from its compact-row
    // position to center while scaling up, reinforcing what action was taken.
    Component {
        id: successComponent

        // Wrapper matches the compact row's dimensions so the card
        // background stays the same size during the success state.
        Item {
            implicitWidth: compactRow.implicitWidth
            implicitHeight: compactRow.implicitHeight

            // Pill-shaped container matching PillButton's matte background,
            // so the icon keeps its dark pill as it slides to center.
            StyledRect {
                id: successPill

                anchors.verticalCenter: parent.verticalCenter

                readonly property real targetIconSize: Appearance.font.size.large
                readonly property real targetPadding: Appearance.padding.normal * 2

                implicitWidth: successIcon.implicitWidth + targetPadding
                implicitHeight: successIcon.implicitHeight + Appearance.padding.smaller * 2

                // Rectangle does not auto-apply implicitWidth/implicitHeight as width/height
                // when placed inside a plain Item (non-layout). Explicit bindings are required.
                width: implicitWidth
                height: implicitHeight

                radius: Appearance.rounding.full
                color: Colours.pillStyle(
                    Colours.palette.m3surfaceContainerHigh,
                    Colours.glass.subtle
                ).background

                opacity: 0

                MaterialIcon {
                    id: successIcon

                    anchors.centerIn: parent
                    text: {
                        if (root.serviceInjectionDowngraded) return "content_copy";
                        switch (root.serviceInjectionPath) {
                            case "rpc":
                                return root.serviceInjectionSubmitted ? "send" : "input";
                            case "paste": return "input";
                            default: return "content_copy";
                        }
                    }
                    color: root.serviceInjectionDowngraded
                        ? Colours.palette.m3error
                        : root.stateConfig.iconColor
                    font.pointSize: successPill.targetIconSize
                }

                Component.onCompleted: {
                    // Start at mode button's position and size, then animate
                    // to center at larger size with overshoot.
                    if (root.serviceIsAskMode) {
                        x = modeBtn.x + modeBtn.width / 2 - width / 2;
                        scale = modeBtn.width / width;
                    } else {
                        x = (parent.width - width) / 2;
                        scale = 0.4;
                    }
                    popAnim.start();
                }

                ParallelAnimation {
                    id: popAnim

                    NumberAnimation {
                        target: successPill
                        property: "x"
                        to: (successPill.parent.width - successPill.width) / 2
                        duration: Appearance.anim.durations.expressiveDefaultSpatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
                    }

                    NumberAnimation {
                        target: successPill
                        property: "scale"
                        to: 1.0
                        duration: Appearance.anim.durations.expressiveDefaultSpatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.anim.curves.expressiveDefaultSpatial
                    }

                    NumberAnimation {
                        target: successPill
                        property: "opacity"
                        to: 1.0
                        duration: Appearance.anim.durations.small
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.anim.curves.emphasizedDecel
                    }
                }
            }
        }
    }

    Component {
        id: errorComponent

        ColumnLayout {
            spacing: Appearance.spacing.small

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: root.stateConfig.icon
                color: root.stateConfig.iconColor
                font.pointSize: Appearance.font.size.extraLarge
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.serviceErrorDetail || qsTr("Transcription failed")
                font.pointSize: Appearance.font.size.normal
                color: Colours.palette.m3error
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.serviceErrorHint || qsTr("Check STT configuration")
                font.pointSize: Appearance.font.size.small
                color: Colours.palette.m3outline
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Appearance.spacing.normal

                PillButton {
                    id: retryBtn
                    visible: root.serviceErrorSource === "api" || root.serviceErrorSource === "timeout"
                    icon: "refresh"
                    iconColor: Colours.palette.m3primary
                    onClicked: root.job.retry()
                }

                PillButton {
                    id: errorCancelBtn
                    icon: "close"
                    iconColor: Colours.palette.m3error
                    onClicked: root.job.cancel()
                }

                PillButton {
                    visible: root.serviceErrorRaw !== ""
                    icon: "content_copy"
                    onClicked: Quickshell.execDetached(["wl-copy", root.serviceErrorRaw])
                }
            }

            // retryBtn and errorCancelBtn only exist in this component's scope,
            // so this Connections block must live here rather than in the outer handler.
            Connections {
                target: SttService
                function onActionTriggered(sessionId: string, action: string): void {
                    if (sessionId !== "" && sessionId !== root.job.sessionId) return;
                    if (root.serviceState !== "error") return;
                    if (action === "retry") retryBtn.triggerPress();
                    else if (action === "cancel") errorCancelBtn.triggerPress();
                }
            }
        }
    }

    implicitWidth: container.implicitWidth
    implicitHeight: container.implicitHeight + Appearance.padding.large

    // Main container
    StyledRect {
        id: container

        anchors.top: parent.top
        anchors.topMargin: Appearance.padding.large
        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth: content.implicitWidth + Appearance.padding.large * 2
        implicitHeight: content.implicitHeight + Appearance.padding.large * 2

        Behavior on implicitHeight {
            enabled: root.enableHeightTransition
            Anim {}
        }

        Behavior on implicitWidth {
            enabled: root.enableHeightTransition
            Anim {}
        }

        radius: Appearance.rounding.normal
        color: "transparent"

        // HoverHandler uses Qt Quick's pointer handler system (parallel delivery),
        // unlike MouseArea which participates in grab exclusivity. Child MouseAreas
        // in chip delegates cannot block this handler from receiving hover events.
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

            // ── Compact row: [timer] · [waveform] · [mode icon] ─────
            FadeTransition {
                Layout.alignment: Qt.AlignHCenter
                show: root.serviceState === "recording" || root.serviceState === "paused" || root.serviceState === "processing"

                RowLayout {
                    id: compactRow

                    spacing: Appearance.spacing.small

                    // Elapsed timer
                    StyledText {
                        opacity: root.serviceState === "paused" ? 0.55 : 1.0
                        text: root.formatElapsedTime(root.serviceElapsedSeconds)
                        font.pointSize: Appearance.font.size.small * 0.88
                        font.family: Appearance.font.family.mono
                        color: Colours.palette.m3outline

                        Behavior on opacity { Anim {} }
                    }

                    // Separator
                    StyledText {
                        text: "·"
                        font.pointSize: Appearance.font.size.small
                        color: Colours.palette.m3outlineVariant
                    }

                    // Audio level bars (compact)
                    SttWaveform {
                        Layout.preferredWidth: implicitWidth
                        Layout.preferredHeight: root.audioBarContainerHeight

                        audioLevel: root.serviceAudioLevel
                        sttState: root.serviceState
                        barCount: root.barCount
                        containerHeight: root.audioBarContainerHeight
                        active: root.visibilities.stt
                    }

                    // Separator before mode icon (hidden when no mode icon)
                    StyledText {
                        visible: root.serviceIsAskMode
                        text: "·"
                        font.pointSize: Appearance.font.size.small
                        color: Colours.palette.m3outlineVariant
                    }

                    // Mode icon — cycles delivery mode on click.
                    // Stays visible during processing so the user can change
                    // mode before transcription completes, and to keep width stable.
                    PillButton {
                        id: modeBtn

                        visible: root.serviceIsAskMode
                        icon: root.deliveryModeIcons[root.serviceDeliveryChoice] ?? "content_copy"
                        onClicked: root.cycleDeliveryMode()
                    }
                }
            }

            // ── Auto-retry indicator ────────────────────────────────
            FadeTransition {
                Layout.alignment: Qt.AlignHCenter
                show: root.serviceAutoRetrying

                StyledText {
                    text: "retrying…"
                    font.pointSize: Appearance.font.size.small
                    font.italic: true
                    color: Colours.palette.m3outline
                }
            }

            // ── Hover-expanded action buttons ────────────────────────
            FadeTransition {
                Layout.alignment: Qt.AlignHCenter
                show: root.hovered
                    && (root.serviceState === "recording" || root.serviceState === "paused")

                RowLayout {
                    spacing: Appearance.spacing.normal

                    PillButton {
                        id: pauseBtn
                        icon: root.serviceState === "paused" ? "play_arrow" : "pause"
                        iconColor: root.serviceState === "paused" ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        onClicked: root.job.recording ? root.job.pause() : root.job.resume()
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
                        onClicked: root.job.cancel()
                    }

                    PillButton {
                        id: submitBtn
                        icon: "check"
                        iconColor: Colours.palette.m3confirm
                        onClicked: root.job.stop()
                    }
                }
            }

            // ── Vocabulary hint chips ────────────────────────────────
            FadeTransition {
                Layout.alignment: Qt.AlignHCenter
                show: SttService.sessionVocabHints.length > 0
                    && (root.serviceState === "recording" || root.serviceState === "paused")

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
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

            // ── IPC action signal handler ────────────────────────────
            // Triggers visual feedback (button squeeze animation) when
            // keybinds fire — the actual work is done by SttService.
            Connections {
                target: SttService
                function onActionTriggered(sessionId: string, action: string): void {
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
                            if (root.serviceState !== "error")
                                cancelBtn.triggerPress();
                            break;
                        case "retry":
                            // Handled by errorComponent's own Connections block
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

            // ── State indicator (success/error) ──────────────────────
            Loader {
                Layout.alignment: Qt.AlignHCenter
                visible: sourceComponent !== null

                sourceComponent: {
                    switch (root.serviceState) {
                        case "success":
                            return successComponent;
                        case "error":
                            return errorComponent;
                        default:
                            return null;
                    }
                }
            }
        }
    }
}
