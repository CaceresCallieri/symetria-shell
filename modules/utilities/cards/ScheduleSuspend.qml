pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

PillCard {
    id: root

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + Appearance.padding.large * 2

    ColumnLayout {
        id: layout

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Appearance.padding.large
        spacing: Appearance.spacing.normal

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.normal

            PillSurface {
                implicitWidth: implicitHeight
                implicitHeight: icon.implicitHeight + Appearance.padding.smaller * 2

                // Same state-brightening recipe as the Keep Awake card so the
                // two utility cards read as siblings.
                color: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, SuspendTimer.running ? Colours.glass.veryStrong : Colours.glass.subtle).background

                MaterialIcon {
                    id: icon

                    anchors.centerIn: parent
                    text: "bedtime"
                    color: Colours.palette.m3onSurface
                    font.pointSize: Appearance.font.size.large
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Schedule Suspend")
                    font.pointSize: Appearance.font.size.normal
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: SuspendTimer.running ? qsTr("Suspending at %1").arg(Qt.formatTime(SuspendTimer.deadline, Config.services.useTwelveHourClock ? "hh:mm a" : "hh:mm")) : qsTr("No suspend scheduled")
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Appearance.font.size.small
                    elide: Text.ElideRight
                }
            }

            StyledSwitch {
                checked: SuspendTimer.running
                onToggled: checked ? SuspendTimer.start(0) : SuspendTimer.cancel()
            }
        }

        // Swap area: duration presets when idle, live countdown when armed.
        // Sized to the taller of the two so the card keeps a constant height
        // across the toggle (unlike Keep Awake, which animates its height).
        Item {
            Layout.fillWidth: true
            implicitHeight: Math.max(presetsRow.implicitHeight, countdownChip.implicitHeight)

            Row {
                id: presetsRow

                anchors.verticalCenter: parent.verticalCenter
                spacing: Appearance.spacing.small
                opacity: SuspendTimer.running ? 0 : 1
                visible: opacity > 0

                Repeater {
                    model: SuspendTimer.presetMinutes

                    DurationChip {}
                }

                Behavior on opacity {
                    Anim {
                        duration: Appearance.anim.durations.small
                    }
                }
            }

            StyledRect {
                id: countdownChip

                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: countdownText.implicitWidth + Appearance.padding.normal * 2
                implicitHeight: countdownText.implicitHeight + Appearance.padding.small * 2

                radius: Appearance.rounding.full
                color: Colours.palette.m3primary
                opacity: SuspendTimer.running ? 1 : 0
                visible: opacity > 0
                scale: SuspendTimer.running ? 1 : 0.5

                StyledText {
                    id: countdownText

                    anchors.centerIn: parent
                    text: qsTr("Suspending in %1").arg(SuspendTimer.remainingText)
                    color: Colours.palette.m3onPrimary
                    font.pointSize: Math.round(Appearance.font.size.small * 0.9)
                }

                Behavior on opacity {
                    Anim {
                        duration: Appearance.anim.durations.small
                    }
                }

                Behavior on scale {
                    Anim {}
                }
            }
        }
    }

    component DurationChip: PillToggleSurface {
        id: chip

        required property int modelData
        readonly property bool selected: SuspendTimer.durationMinutes === modelData

        active: selected
        radius: Appearance.rounding.full
        implicitWidth: chipLabel.implicitWidth + Appearance.padding.normal * 2
        implicitHeight: chipLabel.implicitHeight + Appearance.padding.small * 2

        StateLayer {
            color: chip.selected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface

            function onClicked(): void {
                SuspendTimer.durationMinutes = chip.modelData;
            }
        }

        StyledText {
            id: chipLabel

            anchors.centerIn: parent
            text: `${chip.modelData}m`
            color: chip.selected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            font.pointSize: Appearance.font.size.small

            Behavior on color {
                CAnim {}
            }
        }
    }
}
