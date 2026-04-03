pragma ComponentBehavior: Bound

import qs.components
import qs.components.containers
import qs.services
import qs.config
import Quickshell
import QtQuick
import QtQuick.Layouts

/// Content UI for Keycaster key display.
///
/// Displays a horizontal row of key chips showing recent keypresses and mouse clicks.
/// Newest entries appear on the right, older entries fade out on the left.
Item {
    id: root

    readonly property int padding: Appearance.padding.large
    readonly property int chipSpacing: Appearance.spacing.small

    implicitWidth: container.implicitWidth
    implicitHeight: container.implicitHeight + padding

    // Main container
    StyledRect {
        id: container

        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth: Math.max(200, keyRow.implicitWidth + Appearance.padding.large * 2)
        implicitHeight: keyRow.implicitHeight + Appearance.padding.normal * 2

        // Match Hyprland's window corner rounding proportionally. The raw value
        // (e.g. 24px) would create full capsule ends on a short pill, so cap at
        // height/2.5 to preserve a similar visual curvature to client windows.
        readonly property real hyprRounding: Hypr.options["decoration:rounding"] ?? Appearance.rounding.full
        radius: Math.min(hyprRounding, implicitHeight / 2.5)
        // Pill style background — not reactive to pillStyle config hot-reload (requires shell restart)
        readonly property var pillColors: Colours.pillStyle(Colours.palette.m3surfaceContainerHigh, Colours.glass.subtle)
        color: pillColors.background
        border.color: pillColors.border
        border.width: 1

        RowLayout {
            id: keyRow

            anchors.centerIn: parent
            spacing: root.chipSpacing

            // Zero-width transparent placeholder ensures minimum height when no keys displayed.
            // Using a real KeyChip (not a fixed height) keeps the minimum in sync with chip styling.
            // IMPORTANT: Use opacity:0 (not visible:false) - visible:false excludes from layout!
            KeyChip {
                keyText: "Ctrl+Shift+X"
                isNewest: false
                mouseButton: ""
                opacity: 0
                Layout.maximumWidth: 0
            }

            // Key history chips
            Repeater {
                model: KeycasterService.keyHistory

                KeyChip {
                    required property string key
                    required property int keyId
                    required property int timestamp
                    required property int index

                    // mouseButton uses `required` (without type) to make KeyChip's
                    // EXISTING property required rather than creating a shadow property.
                    // `required property string mouseButton` would shadow it, leaving
                    // KeyChip's own mouseButton stuck at "".
                    required mouseButton

                    keyText: key
                    isNewest: index === KeycasterService.keyHistory.count - 1
                    keyTimestamp: timestamp
                }
            }
        }
    }
}
