pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

// System monitoring pill - wraps CpuStatus, RamUsage, and AvailableUpdates
// in a glassmorphism container. Uses PillContainer base for consistent styling.
// Note: Only AvailableUpdates currently supports hover popout (see Bar.qml checkPopout).

PillContainer {
    id: root

    // Use tertiary color for time/system info pills (vs secondary for status icons).
    property color colour: Colours.palette.m3tertiary

    // Expose content for popout detection (matches StatusIcons/TimePill pattern)
    property alias iconContainer: content

    // Hide entirely when no items are visible
    visible: Config.bar.systemPill.showCpu
        || Config.bar.systemPill.showRam
        || Config.bar.systemPill.showUpdates

    RowLayout {
        id: content

        anchors.centerIn: parent
        spacing: Appearance.spacing.small

        // Left padding spacer
        Item {
            implicitWidth: root.pillPadding
            implicitHeight: 1
        }

        // CPU Status
        PillContainer.WrappedLoader {
            name: "cpu"
            active: Config.bar.systemPill.showCpu

            sourceComponent: CpuStatus {
                colour: root.colour
            }
        }

        // RAM Usage
        PillContainer.WrappedLoader {
            name: "ram"
            active: Config.bar.systemPill.showRam

            sourceComponent: RamUsage {
                colour: root.colour
            }
        }

        // Available Updates
        PillContainer.WrappedLoader {
            name: "updates"
            active: Config.bar.systemPill.showUpdates

            sourceComponent: AvailableUpdates {
                colour: root.colour
            }
        }

        // Right padding spacer
        Item {
            implicitWidth: root.pillPadding
            implicitHeight: 1
        }
    }
}
