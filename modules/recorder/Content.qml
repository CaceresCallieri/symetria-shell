pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.config
import qs.modules.stt as SttModule
import Quickshell
import QtQuick
import QtQuick.Layouts

/// Content UI for the recorder drawer card.
///
/// Compact horizontal layout:
/// - Default: [MM:SS] · [waveform] · [mic icon]
/// - Hover: action buttons (pause, cancel, stop)
///
/// Terminal states (error, success) replace the compact row.
Item {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities
    readonly property AudioRecorderJob job: AudioRecorderService.job

    property bool enableHeightTransition: false
    property bool hovered: false

    Timer {
        id: hoverDebounce
        interval: 150
        onTriggered: root.hovered = false
    }

    // Map "saving" → "processing" for waveform display
    readonly property string displayState: {
        const s = job?.state ?? "idle";
        if (s === "saving") return "processing";
        return s;
    }
    readonly property real audioLevel: job?.audioLevel ?? 0
    readonly property real elapsedSeconds: job?.elapsedSeconds ?? 0

    readonly property int barCount: 16
    readonly property int audioBarContainerHeight: 24

    function formatElapsedTime(seconds: real): string {
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return mins.toString().padStart(2, '0') + ':' + secs.toString().padStart(2, '0');
    }

    readonly property var stateMap: ({
        "recording": {
            icon: "mic",
            iconColor: Colours.palette.m3error
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
            icon: "check_circle",
            iconColor: Colours.palette.m3confirm
        },
        "idle": {
            icon: "mic",
            iconColor: Colours.palette.m3onSurface
        }
    })

    readonly property var stateConfig: stateMap[root.displayState] ?? stateMap["idle"]

    // ── Success component ──────────────────────────────────────────
    Component {
        id: successComponent

        Item {
            implicitWidth: compactRow.implicitWidth
            implicitHeight: compactRow.implicitHeight

            StyledRect {
                id: successPill

                anchors.verticalCenter: parent.verticalCenter

                readonly property real targetIconSize: Appearance.font.size.large
                readonly property real targetPadding: Appearance.padding.normal * 2

                implicitWidth: successIcon.implicitWidth + targetPadding
                implicitHeight: successIcon.implicitHeight + Appearance.padding.smaller * 2
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
                    text: "audio_file"
                    color: root.stateConfig.iconColor
                    font.pointSize: successPill.targetIconSize
                }

                Component.onCompleted: {
                    x = (parent.width - width) / 2;
                    scale = 0.4;
                    popAnim.start();
                }

                ParallelAnimation {
                    id: popAnim

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

    // ── Error component ────────────────────────────────────────────
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
                text: root.job?.errorDetail ?? qsTr("Recording failed")
                font.pointSize: Appearance.font.size.normal
                color: Colours.palette.m3error
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.job?.errorHint ?? qsTr("Check audio configuration")
                font.pointSize: Appearance.font.size.small
                color: Colours.palette.m3outline
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Appearance.spacing.normal

                PillButton {
                    id: errorCancelBtn
                    icon: "close"
                    iconColor: Colours.palette.m3error
                    onClicked: root.job.cancel()
                }
            }

            Connections {
                target: AudioRecorderService
                function onActionTriggered(action: string): void {
                    if (root.displayState !== "error") return;
                    if (action === "cancel") errorCancelBtn.triggerPress();
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

            // ── Compact row: [timer] · [waveform] · [state icon] ───
            FadeTransition {
                Layout.alignment: Qt.AlignHCenter
                show: root.displayState === "recording" || root.displayState === "paused" || root.displayState === "processing"

                RowLayout {
                    id: compactRow

                    spacing: Appearance.spacing.small

                    StyledText {
                        opacity: root.displayState === "paused" ? 0.55 : 1.0
                        text: root.formatElapsedTime(root.elapsedSeconds)
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

                    // Reused STT waveform component
                    SttModule.SttWaveform {
                        Layout.preferredWidth: implicitWidth
                        Layout.preferredHeight: root.audioBarContainerHeight

                        audioLevel: root.audioLevel
                        sttState: root.displayState
                        barCount: root.barCount
                        containerHeight: root.audioBarContainerHeight
                        active: root.visibilities.recorder
                    }

                    StyledText {
                        text: "·"
                        font.pointSize: Appearance.font.size.small
                        color: Colours.palette.m3outlineVariant
                    }

                    // State indicator icon
                    MaterialIcon {
                        text: root.stateConfig.icon
                        color: root.stateConfig.iconColor
                        font.pointSize: Appearance.font.size.small
                    }
                }
            }

            // ── Hover-expanded action buttons ──────────────────────
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
                        onClicked: AudioRecorderService.pause()
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
                        onClicked: AudioRecorderService.stop()
                    }
                }
            }

            // ── IPC action feedback ───────────────────────────────
            Connections {
                target: AudioRecorderService
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

            // ── State indicator (success/error) ───────────────────
            Loader {
                Layout.alignment: Qt.AlignHCenter
                visible: sourceComponent !== null

                sourceComponent: {
                    switch (root.displayState) {
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
