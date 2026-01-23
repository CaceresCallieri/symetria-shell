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

    // Cached bar gradient colors - invalidated only on theme change
    // Using explicit Connections instead of bindings prevents unnecessary recalculation
    property var barColors: []

    function updateBarColors() {
        const colors = [];
        for (let i = 0; i < barCount; i++) {
            const t = i / barCount;
            colors.push(Qt.tint(Colours.palette.m3primary,
                Qt.rgba(Colours.palette.m3tertiary.r,
                        Colours.palette.m3tertiary.g,
                        Colours.palette.m3tertiary.b,
                        t * 0.5)));
        }
        barColors = colors;
    }

    Component.onCompleted: updateBarColors()

    Connections {
        target: Colours.palette
        function onM3primaryChanged() { root.updateBarColors(); }
        function onM3tertiaryChanged() { root.updateBarColors(); }
    }

    // Pre-calculated wave offsets - computed once per frame instead of per-bar
    // Reduces Math.sin() calls from 1200/sec (20 bars × 60fps) to 60/sec
    readonly property var waveOffsets: {
        if (HyprWhsprService.state !== "recording") return [];
        const cfg = audioConfig;
        const offsets = [];
        for (let i = 0; i < barCount; i++) {
            offsets.push(Math.sin(i * cfg.waveFrequency + animationTime * cfg.waveSpeed) * cfg.waveVariation + (1 - cfg.waveVariation));
        }
        return offsets;
    }

    // State configuration map - single source of truth for all state-dependent UI
    // Using a map instead of multiple switch statements improves maintainability
    readonly property var stateMap: ({
        "recording": {
            icon: "mic",
            iconColor: Colours.palette.m3primary,
            statusText: qsTr("Recording..."),
            textColor: Colours.palette.m3onSurface
        },
        "processing": {
            icon: "hourglass_top",
            iconColor: Colours.palette.m3secondary,
            statusText: qsTr("Transcribing..."),
            textColor: Colours.palette.m3onSurface
        },
        "error": {
            icon: "error",
            iconColor: Colours.palette.m3error,
            statusText: qsTr("Failed"),
            textColor: Colours.palette.m3error
        },
        "success": {
            icon: "check_circle",
            iconColor: Colours.palette.m3primary,
            statusText: qsTr("Done!"),
            textColor: Colours.palette.m3onSurface
        },
        "idle": {
            icon: "mic",
            iconColor: Colours.palette.m3onSurface,
            statusText: "",
            textColor: Colours.palette.m3onSurface
        }
    })

    // Current state config - falls back to idle for unknown states
    readonly property var stateConfig: stateMap[HyprWhsprService.state] ?? stateMap["idle"]

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
            FadeTransition {
                id: audioLevelContainer

                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: audioLevelRow.implicitWidth
                Layout.preferredHeight: root.audioBarContainerHeight

                show: HyprWhsprService.state === "recording"

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

                                // Use pre-calculated wave offset (computed once per frame at root level)
                                const waveOffset = root.waveOffsets[index] ?? 1.0;
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
            FadeTransition {
                Layout.alignment: Qt.AlignHCenter
                show: HyprWhsprService.state === "error"

                StyledText {
                    text: qsTr("Check hyprwhspr logs for details")
                    font.pointSize: Appearance.font.size.small
                    color: Colours.palette.m3outline
                }
            }

            // Cancel button (visible during processing)
            FadeTransition {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Appearance.spacing.small
                show: HyprWhsprService.state === "processing"

                TextButton {
                    text: qsTr("Cancel")
                    inactiveColour: Colours.palette.m3secondaryContainer
                    inactiveOnColour: Colours.palette.m3onSecondaryContainer
                    onClicked: HyprWhsprService.cancel()
                }
            }
        }
    }
}
