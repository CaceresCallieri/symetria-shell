pragma ComponentBehavior: Bound

import qs.components
import qs.components.controls
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

/// Workspaces settings section for the Taskbar settings pane.
/// Contains: workspace count spinbox + 6 switch rows for workspace behavior.
/// Extracted from TaskbarPane.qml to reduce file size.
SectionContainer {
    id: root

    Layout.fillWidth: true
    alignTop: true

    required property int shown
    required property bool showOnlyOccupied
    required property bool activeIndicator
    required property bool occupiedBg
    required property bool showWindows
    required property bool perMonitor
    required property color pillBackground
    required property color pillBorder

    /// Emitted when any setting changes. The parent should update
    /// its mirrored property and call saveConfig().
    signal settingChanged(string name, var value) // intentional var: heterogeneous — int for 'shown', bool for switches

    StyledText {
        text: qsTr("Workspaces")
        font.pointSize: Appearance.font.size.normal
    }

    // Workspaces shown (spinbox)
    StyledRect {
        Layout.fillWidth: true
        implicitHeight: workspacesShownRow.implicitHeight + Appearance.padding.large * 2
        radius: Appearance.rounding.normal
        color: root.pillBackground
        border.color: root.pillBorder
        border.width: 1

        Behavior on implicitHeight {
            Anim {}
        }

        RowLayout {
            id: workspacesShownRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Appearance.padding.large
            spacing: Appearance.spacing.normal

            StyledText {
                Layout.fillWidth: true
                opacity: root.showOnlyOccupied ? 0.5 : 1.0
                text: qsTr("Shown")
            }

            CustomSpinBox {
                enabled: !root.showOnlyOccupied
                min: 1
                max: 20
                value: root.shown
                onValueModified: value => {
                    root.settingChanged("workspacesShown", value);
                }
            }
        }
    }

    // Show only occupied
    StyledRect {
        Layout.fillWidth: true
        implicitHeight: workspacesShowOnlyOccupiedRow.implicitHeight + Appearance.padding.large * 2
        radius: Appearance.rounding.normal
        color: root.pillBackground
        border.color: root.pillBorder
        border.width: 1

        Behavior on implicitHeight {
            Anim {}
        }

        RowLayout {
            id: workspacesShowOnlyOccupiedRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Appearance.padding.large
            spacing: Appearance.spacing.normal

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Show only occupied")
            }

            StyledSwitch {
                checked: root.showOnlyOccupied
                onToggled: {
                    root.settingChanged("workspacesShowOnlyOccupied", checked);
                }
            }
        }
    }

    // Active indicator
    StyledRect {
        Layout.fillWidth: true
        implicitHeight: workspacesActiveIndicatorRow.implicitHeight + Appearance.padding.large * 2
        radius: Appearance.rounding.normal
        color: root.pillBackground
        border.color: root.pillBorder
        border.width: 1

        Behavior on implicitHeight {
            Anim {}
        }

        RowLayout {
            id: workspacesActiveIndicatorRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Appearance.padding.large
            spacing: Appearance.spacing.normal

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Active indicator")
            }

            StyledSwitch {
                checked: root.activeIndicator
                onToggled: {
                    root.settingChanged("workspacesActiveIndicator", checked);
                }
            }
        }
    }

    // Occupied background
    StyledRect {
        Layout.fillWidth: true
        implicitHeight: workspacesOccupiedBgRow.implicitHeight + Appearance.padding.large * 2
        radius: Appearance.rounding.normal
        color: root.pillBackground
        border.color: root.pillBorder
        border.width: 1

        Behavior on implicitHeight {
            Anim {}
        }

        RowLayout {
            id: workspacesOccupiedBgRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Appearance.padding.large
            spacing: Appearance.spacing.normal

            StyledText {
                Layout.fillWidth: true
                opacity: root.showOnlyOccupied ? 0.5 : 1.0
                text: qsTr("Occupied background")
            }

            StyledSwitch {
                enabled: !root.showOnlyOccupied
                checked: root.occupiedBg
                onToggled: {
                    root.settingChanged("workspacesOccupiedBg", checked);
                }
            }
        }
    }

    // Show windows
    StyledRect {
        Layout.fillWidth: true
        implicitHeight: workspacesShowWindowsRow.implicitHeight + Appearance.padding.large * 2
        radius: Appearance.rounding.normal
        color: root.pillBackground
        border.color: root.pillBorder
        border.width: 1

        Behavior on implicitHeight {
            Anim {}
        }

        RowLayout {
            id: workspacesShowWindowsRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Appearance.padding.large
            spacing: Appearance.spacing.normal

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Show windows")
            }

            StyledSwitch {
                checked: root.showWindows
                onToggled: {
                    root.settingChanged("workspacesShowWindows", checked);
                }
            }
        }
    }

    // Per monitor workspaces
    StyledRect {
        Layout.fillWidth: true
        implicitHeight: workspacesPerMonitorRow.implicitHeight + Appearance.padding.large * 2
        radius: Appearance.rounding.normal
        color: root.pillBackground
        border.color: root.pillBorder
        border.width: 1

        Behavior on implicitHeight {
            Anim {}
        }

        RowLayout {
            id: workspacesPerMonitorRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Appearance.padding.large
            spacing: Appearance.spacing.normal

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Per monitor workspaces")
            }

            StyledSwitch {
                checked: root.perMonitor
                onToggled: {
                    root.settingChanged("workspacesPerMonitor", checked);
                }
            }
        }
    }
}
