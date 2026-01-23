pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

/// Content UI for HyprWhsprService speech-to-text drawer.
///
/// Displays state-based UI:
/// - recording: Pulsing mic icon + audio level bars
/// - processing: Spinner + "Transcribing..."
/// - error: Error icon + retry hint (future)
/// - success: Checkmark, brief display before auto-hide (future)
Item {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities

    readonly property int padding: Appearance.padding.large
    readonly property int rounding: Appearance.rounding.large

    // Number of audio visualizer bars
    readonly property int barCount: 20
    // Minimum drawer width for readability
    readonly property int minDrawerWidth: 300
    // Height of audio level bar container
    readonly property int audioBarContainerHeight: 48

    // Audio visualization tuning constants
    readonly property QtObject audioConfig: QtObject {
        readonly property real smoothing: 0.35       // Lower = smoother/slower response
        readonly property real noiseFloor: 0.10      // Ambient noise threshold (0-1)
        readonly property real powerCurve: 1.1       // >1 boosts loud, <1 boosts quiet
        readonly property real waveVariation: 0.30   // ±30% height variation
        readonly property real waveSpeed: 0.08       // Animation speed multiplier
        readonly property real waveFrequency: 0.8    // Sine wave frequency across bars
        readonly property real minBarHeight: 2
        readonly property real maxBarHeight: 44
    }

    // Audio level from service (exposed for Repeater delegates under ComponentBehavior: Bound)
    readonly property real audioLevel: HyprWhsprService.audioLevel

    // Animation time for audio bar noise (avoids Date.now() per-frame overhead)
    // Increments ~60 units per second for smooth sine wave oscillation
    property real animationTime: 0

    NumberAnimation on animationTime {
        running: HyprWhsprService.state === "recording"
        from: 0
        to: 6000
        duration: 100000  // 100 seconds before loop (60 units/sec)
        loops: Animation.Infinite
    }

    // Pre-calculated bar gradient colors (avoids recalculating on every frame)
    readonly property var barColors: {
        const colors = [];
        for (let i = 0; i < barCount; i++) {
            const t = i / barCount;
            colors.push(Qt.tint(Colours.palette.m3primary,
                Qt.rgba(Colours.palette.m3tertiary.r,
                        Colours.palette.m3tertiary.g,
                        Colours.palette.m3tertiary.b,
                        t * 0.5)));
        }
        return colors;
    }

    // State configuration - centralized to avoid duplicate switch statements
    QtObject {
        id: stateConfig

        readonly property string icon: {
            switch (HyprWhsprService.state) {
            case "recording":
                return "mic";
            case "processing":
                return "hourglass_top";
            case "error":
                return "error";
            case "success":
                return "check_circle";
            default:
                return "mic";
            }
        }

        readonly property color iconColor: {
            switch (HyprWhsprService.state) {
            case "recording":
                return Colours.palette.m3primary;
            case "processing":
                return Colours.palette.m3secondary;
            case "error":
                return Colours.palette.m3error;
            case "success":
                return Colours.palette.m3primary;
            default:
                return Colours.palette.m3onSurface;
            }
        }

        readonly property string statusText: {
            switch (HyprWhsprService.state) {
            case "recording":
                return qsTr("Recording...");
            case "processing":
                return qsTr("Transcribing...");
            case "error":
                return qsTr("Failed");
            case "success":
                return qsTr("Done!");
            default:
                return "";
            }
        }

        readonly property color textColor: {
            if (HyprWhsprService.state === "error")
                return Colours.palette.m3error;
            return Colours.palette.m3onSurface;
        }
    }

    implicitWidth: container.implicitWidth
    implicitHeight: container.implicitHeight + padding

    // Main container
    StyledRect {
        id: container

        anchors.top: parent.top
        anchors.topMargin: root.padding
        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth: Math.max(root.minDrawerWidth, content.implicitWidth + Appearance.padding.large * 2)
        implicitHeight: content.implicitHeight + Appearance.padding.large * 2

        radius: Appearance.rounding.normal
        color: "transparent"

        ColumnLayout {
            id: content

            anchors.centerIn: parent
            spacing: Appearance.spacing.normal

            // Status row: Icon + Text
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Appearance.spacing.normal

                // State-based icon
                MaterialIcon {
                    id: stateIcon

                    Layout.preferredWidth: Appearance.font.size.extraLarge
                    Layout.preferredHeight: Appearance.font.size.extraLarge

                    text: stateConfig.icon
                    color: stateConfig.iconColor
                    font.pointSize: Appearance.font.size.extraLarge

                    // Pulsing animation for recording state
                    SequentialAnimation on opacity {
                        running: HyprWhsprService.state === "recording"
                        loops: Animation.Infinite

                        NumberAnimation {
                            from: 1.0
                            to: 0.5
                            duration: 500
                            easing.type: Easing.InOutSine
                        }
                        NumberAnimation {
                            from: 0.5
                            to: 1.0
                            duration: 500
                            easing.type: Easing.InOutSine
                        }
                    }

                    // Spinning animation for processing state
                    RotationAnimation on rotation {
                        running: HyprWhsprService.state === "processing"
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 1500
                    }
                }

                // Status text
                StyledText {
                    id: statusText

                    text: stateConfig.statusText
                    font.pointSize: Appearance.font.size.large
                    font.weight: 500
                    color: stateConfig.textColor
                }
            }

            // Audio level bars (only visible during recording)
            Item {
                id: audioLevelContainer

                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: audioLevelRow.implicitWidth
                Layout.preferredHeight: root.audioBarContainerHeight

                visible: HyprWhsprService.state === "recording"
                opacity: visible ? 1 : 0

                Behavior on opacity {
                    Anim {}
                }

                Row {
                    id: audioLevelRow

                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: root.barCount

                        Rectangle {
                            id: bar

                            required property int index

                            // Bar height based on audio level and position
                            // Center bars are taller, edges shorter (bell curve effect)
                            readonly property real positionFactor: {
                                const center = root.barCount / 2;
                                const distance = Math.abs(index - center) / center;
                                return 1 - distance * 0.5;  // 0.5 to 1.0
                            }

                            // The "truth" - raw target from audio level (updates at 60fps)
                            readonly property real targetHeight: {
                                const cfg = root.audioConfig;
                                const rawLevel = root.audioLevel;

                                // Noise gate: ignore fan noise and ambient sounds
                                let effectiveLevel = 0;
                                if (rawLevel > cfg.noiseFloor) {
                                    // Rescale: map [noiseFloor, 1.0] → [0, 1.0]
                                    effectiveLevel = (rawLevel - cfg.noiseFloor) / (1.0 - cfg.noiseFloor);
                                    // Power curve adjusts quiet vs loud response
                                    effectiveLevel = Math.pow(effectiveLevel, cfg.powerCurve);
                                }

                                const waveOffset = Math.sin(index * cfg.waveFrequency + root.animationTime * cfg.waveSpeed) * cfg.waveVariation + (1 - cfg.waveVariation);
                                return cfg.minBarHeight + effectiveLevel * (cfg.maxBarHeight - cfg.minBarHeight) * positionFactor * waveOffset;
                            }

                            // The "display" - smoothed version for rendering
                            property real smoothedHeight: root.audioConfig.minBarHeight

                            // Manual exponential smoothing - runs every time target changes
                            onTargetHeightChanged: {
                                smoothedHeight = smoothedHeight + (targetHeight - smoothedHeight) * root.audioConfig.smoothing;
                            }

                            // Direct sizing - Row doesn't support Layout.* properties,
                            // and anchors.verticalCenter conflicts with Row positioning
                            width: 5
                            height: smoothedHeight
                            y: (parent.height - height) / 2  // Manual vertical centering

                            radius: 2.5
                            color: root.barColors[index] ?? Colours.palette.m3primary
                        }
                    }
                }
            }

            // Hint text for error state
            StyledText {
                Layout.alignment: Qt.AlignHCenter

                visible: HyprWhsprService.state === "error"
                opacity: visible ? 1 : 0

                text: qsTr("Check hyprwhspr logs for details")

                font.pointSize: Appearance.font.size.small
                color: Colours.palette.m3outline

                Behavior on opacity {
                    Anim {}
                }
            }

            // Cancel button (visible during processing)
            TextButton {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Appearance.spacing.small

                visible: HyprWhsprService.state === "processing"
                opacity: visible ? 1 : 0

                text: qsTr("Cancel")
                inactiveColour: Colours.palette.m3secondaryContainer
                inactiveOnColour: Colours.palette.m3onSecondaryContainer

                onClicked: HyprWhsprService.cancel()

                Behavior on opacity {
                    Anim {}
                }
            }
        }
    }
}
