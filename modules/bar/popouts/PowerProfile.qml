pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

// Compact popout for the dedicated power-profile status icon. Just a label
// showing the current profile name plus the four neumorphic ProfilePill
// toggles (Silent + the three PPD profiles). Visual language matches the selector inside the Battery popout
// (intentional — same component, no drift) but trimmed of battery-specific
// telemetry so the icon's purpose is unambiguous.
PillCardSection {
    id: root

    implicitWidth: layout.implicitWidth + root.contentMargins * 2

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Appearance.spacing.normal

        StyledText {
            text: qsTr("Power profile: %1").arg(PowerMode.activeMode.label)
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

                Row {
                    id: child

                    anchors.centerIn: parent
                    spacing: Appearance.spacing.small

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -font.pointSize / 10

                        text: "warning"
                        color: Colours.palette.m3onError
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Degraded: %1").arg(PerformanceDegradationReason.toString(PowerProfiles.degradationReason))
                        color: Colours.palette.m3onError
                    }
                }
            }
        }

        RowLayout {
            Layout.topMargin: Appearance.spacing.small
            Layout.fillWidth: true
            spacing: Appearance.spacing.small

            // Pills are generated from PowerMode.modes (the single source of
            // truth shared with the bar icon's cycle), so a new mode appears
            // here automatically. The list is a stable literal, so a plain
            // Repeater is fine — no ScriptModel keying needed.
            Repeater {
                model: PowerMode.modes

                ProfilePill {
                    required property var modelData

                    mode: modelData
                }
            }
        }
    }
}
