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
    readonly property int audioBarContainerHeight: 32

    // Animation time for audio bar noise (avoids Date.now() per-frame overhead)
    property real animationTime: 0

    NumberAnimation on animationTime {
        running: HyprWhsprService.state === "recording"
        from: 0
        to: 1000000
        duration: 1000000000  // ~11.5 days - effectively infinite
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

                RowLayout {
                    id: audioLevelRow

                    anchors.centerIn: parent
                    spacing: 2

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

                            readonly property real targetHeight: {
                                const level = HyprWhsprService.audioLevel;
                                // Add some randomization for visual interest using animation time
                                // (avoids Date.now() overhead - 1200+ calls/sec across 20 bars)
                                const noise = Math.sin(index * 0.7 + root.animationTime * 0.005) * 0.1 + 0.9;
                                return Math.max(4, level * 28 * positionFactor * noise);
                            }

                            Layout.preferredWidth: 4
                            Layout.preferredHeight: targetHeight
                            Layout.alignment: Qt.AlignVCenter

                            radius: 2
                            // Use pre-calculated gradient colors for performance
                            color: root.barColors[index]

                            Behavior on Layout.preferredHeight {
                                NumberAnimation {
                                    duration: 50
                                    easing.type: Easing.OutQuad
                                }
                            }
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
