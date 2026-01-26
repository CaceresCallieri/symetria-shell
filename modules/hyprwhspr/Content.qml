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
/// - recording: Animated audio level bars
/// - paused: Static audio level bars with pause icon
/// - processing: Loading spinner
/// - error: Error icon + hint text
/// - success: Checkmark, brief display before auto-hide
Item {
    id: root

    required property ShellScreen screen
    required property PersistentProperties visibilities
    required property string serviceState
    required property real serviceAudioLevel

    readonly property int padding: Appearance.padding.large
    readonly property int rounding: Appearance.rounding.large

    // Number of audio visualizer bars
    readonly property int barCount: 20
    // Minimum drawer width for readability
    readonly property int minDrawerWidth: 300
    // Height of audio level bar container
    readonly property int audioBarContainerHeight: 48

    // Audio visualization tuning constants
    // Tuned for natural speech visualization. Adjust if bars feel laggy/jittery.
    readonly property QtObject audioConfig: QtObject {
        readonly property real smoothing: 0.35       // 0.2=laggy, 0.5=jittery, 0.35=balanced
        readonly property real noiseFloor: 0.10      // Filters ~40dB ambient noise
        readonly property real powerCurve: 1.1       // Slight boost for speech dynamics
        readonly property real waveVariation: 0.30   // ±30% creates motion without chaos
        readonly property real waveSpeed: 0.08       // Gentle oscillation speed
        readonly property real waveFrequency: 0.8    // Wave pattern across bar array
        readonly property real minBarHeight: 2
        readonly property real maxBarHeight: 44
    }

    // Audio level from service (exposed for Repeater delegates under ComponentBehavior: Bound)
    readonly property real audioLevel: root.serviceAudioLevel

    // Animation time for audio bar noise (avoids Date.now() per-frame overhead)
    // Increments ~60 units per second for smooth sine wave oscillation
    property real animationTime: 0

    NumberAnimation on animationTime {
        running: root.serviceState === "recording"
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
        if (root.serviceState !== "recording") return [];
        const cfg = audioConfig;
        const offsets = [];
        for (let i = 0; i < barCount; i++) {
            // Sine wave oscillates around a baseline (e.g., waveVariation=0.30 → baseline=0.70)
            // This creates ±30% height variation while keeping bars visible
            const baseline = 1 - cfg.waveVariation;
            offsets.push(Math.sin(i * cfg.waveFrequency + animationTime * cfg.waveSpeed) * cfg.waveVariation + baseline);
        }
        return offsets;
    }

    // State configuration map - defines visual properties for each state.
    // icon/iconColor are used by the state indicator Loader below.
    readonly property var stateMap: ({
        "recording": {
            icon: "mic",
            iconColor: Colours.palette.m3primary,
            statusText: qsTr("Recording..."),
            textColor: Colours.palette.m3onSurface
        },
        "paused": {
            icon: "pause",
            iconColor: Colours.palette.m3tertiary,
            statusText: qsTr("Paused"),
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
    readonly property var stateConfig: stateMap[root.serviceState] ?? stateMap["idle"]

    // State indicator components - dispatched by the Loader in the content layout.
    // Shared icon component for paused and success (same structure, different icon/color).
    // When transitioning between these two states, Loader reuses the instance and
    // bindings update reactively — no destruction/recreation flicker.
    Component {
        id: stateIconComponent

        MaterialIcon {
            text: root.stateConfig.icon
            color: root.stateConfig.iconColor
            font.pointSize: Appearance.font.size.extraLarge
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
                text: qsTr("Check hyprwhspr logs for details")
                font.pointSize: Appearance.font.size.small
                color: Colours.palette.m3outline
            }
        }
    }

    Component {
        id: processingComponent

        CircularIndicator {
            running: true
            implicitSize: Appearance.font.size.large * 2
            strokeWidth: Appearance.padding.small * 0.6
            fgColour: Colours.palette.m3secondary
            bgColour: Colours.palette.m3secondaryContainer
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

            // Audio level bars (visible during recording and paused)
            // Animation only runs during recording; bars freeze during paused
            FadeTransition {
                id: audioLevelContainer

                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: audioLevelRow.implicitWidth
                Layout.preferredHeight: root.audioBarContainerHeight

                show: root.serviceState === "recording" || root.serviceState === "paused"

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

                            // Direct sizing required because:
                            // 1. Row children can't use Layout.* properties (Row isn't a Layout)
                            // 2. anchors.verticalCenter conflicts with Row's child positioning
                            // 3. Therefore we calculate y manually for vertical centering
                            width: 5
                            height: smoothedHeight
                            y: (parent.height - height) / 2

                            radius: 2.5
                            color: root.barColors[index] ?? Colours.palette.m3primary
                        }
                    }
                }
            }

            // State indicator - dispatches to the appropriate component per state.
            // recording/idle → null (audio bars handle recording; idle = drawer closing)
            // paused/success → stateIconComponent (driven by stateMap icon/iconColor)
            // error → errorComponent (icon + hint text)
            // processing → processingComponent (spinner)
            Loader {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: root.serviceState === "processing" ? Appearance.spacing.small : 0

                sourceComponent: {
                    switch (root.serviceState) {
                        case "paused":
                        case "success":
                            return stateIconComponent;
                        case "error":
                            return errorComponent;
                        case "processing":
                            return processingComponent;
                        default:
                            return null;
                    }
                }
            }
        }
    }
}
