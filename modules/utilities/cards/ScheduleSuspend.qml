pragma ComponentBehavior: Bound

import qs.components
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

        UtilityCardHeader {
            icon: "bedtime"
            title: qsTr("Schedule Suspend")
            subtitle: SuspendTimer.running ? qsTr("Suspending at %1").arg(Qt.formatTime(SuspendTimer.deadline, Config.services.useTwelveHourClock ? "hh:mm a" : "hh:mm")) : qsTr("No suspend scheduled")
            active: SuspendTimer.running
            onToggled: checked => checked ? SuspendTimer.start(0) : SuspendTimer.cancel()
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
