pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

PillCardSection {
    id: root

    implicitWidth: Config.bar.sizes.batteryWidth

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Appearance.spacing.normal

        StyledText {
            text: UPower.displayDevice.isLaptopBattery ? qsTr("Remaining: %1%").arg(Math.round(UPower.displayDevice.percentage * 100)) : qsTr("No battery detected")
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap

            function formatSeconds(s: int, fallback: string): string {
                const day = Math.floor(s / 86400);
                const hr = Math.floor(s / 3600) % 60;
                const min = Math.floor(s / 60) % 60;

                let comps = [];
                if (day > 0)
                    comps.push(`${day} days`);
                if (hr > 0)
                    comps.push(`${hr} hours`);
                if (min > 0)
                    comps.push(`${min} mins`);

                return comps.join(", ") || fallback;
            }

            text: UPower.displayDevice.isLaptopBattery ? qsTr("Time %1: %2").arg(UPower.onBattery ? "remaining" : "until charged").arg(UPower.onBattery ? formatSeconds(UPower.displayDevice.timeToEmpty, "Calculating...") : formatSeconds(UPower.displayDevice.timeToFull, "Fully charged!")) : qsTr("Power profile: %1").arg(PowerProfile.toString(PowerProfiles.profile))
        }

        Loader {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: active ? (item?.implicitHeight ?? 0) : 0

            active: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
            asynchronous: true

            sourceComponent: StyledRect {
                implicitWidth: child.implicitWidth + Appearance.padding.normal * 2
                implicitHeight: child.implicitHeight + Appearance.padding.smaller * 2

                color: Colours.palette.m3powerButton
                radius: Appearance.rounding.normal

                Column {
                    id: child

                    anchors.centerIn: parent

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Appearance.spacing.small

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -font.pointSize / 10

                            text: "warning"
                            color: Colours.palette.m3onError
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Performance Degraded")
                            color: Colours.palette.m3onError
                            font.family: Appearance.font.family.mono
                            font.weight: 500
                        }

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -font.pointSize / 10

                            text: "warning"
                            color: Colours.palette.m3onError
                        }
                    }

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter

                        text: qsTr("Reason: %1").arg(PerformanceDegradationReason.toString(PowerProfiles.degradationReason))
                        color: Colours.palette.m3onError
                    }
                }
            }
        }

        // Power profile selector — three independent neumorphic toggle
        // pills replace the prior sliding-indicator track. Each pill's
        // `active` binding lights only when its profile matches the
        // current PowerProfiles.profile, so the selected profile reads
        // as pressed-in (inset) while the others stay raised. This
        // matches the shell's broader toggle language used elsewhere.
        RowLayout {
            Layout.topMargin: Appearance.spacing.small
            Layout.fillWidth: true
            spacing: Appearance.spacing.small

            ProfilePill {
                profile: PowerProfile.PowerSaver
                icon: "energy_savings_leaf"
            }

            ProfilePill {
                profile: PowerProfile.Balanced
                icon: "balance"
            }

            ProfilePill {
                profile: PowerProfile.Performance
                icon: "rocket_launch"
            }
        }
    }
}
