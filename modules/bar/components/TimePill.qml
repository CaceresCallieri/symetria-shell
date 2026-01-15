pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

// Time display pill - wraps Clock and Date components in a glassmorphism container.
// Uses PillContainer base for consistent styling with other bar pills.

PillContainer {
    id: root

    // Use tertiary color for time/system info pills (vs secondary for status icons).
    property color colour: Colours.palette.m3tertiary

    // Popout interface for calendar popout (planned feature)
    iconContainer: content

    // Hide entirely when no items are visible
    visible: Config.bar.timePill.showClock || Config.bar.timePill.showDate

    // Note: Child components (Clock, Date) may display icons based on Config.bar.clock.showIcon
    // and Config.bar.date.showIcon respectively. When both are shown, this creates an
    // icon-time-icon-date pattern which is intentional for visual identification.

    RowLayout {
        id: content

        anchors.centerIn: parent
        spacing: Appearance.spacing.small

        // Left padding spacer
        Item {
            implicitWidth: root.pillPadding
            implicitHeight: 1
        }

        // Clock
        PillContainer.WrappedLoader {
            name: "clock"
            active: Config.bar.timePill.showClock

            sourceComponent: Clock {
                colour: root.colour
            }
        }

        // Date
        PillContainer.WrappedLoader {
            name: "date"
            active: Config.bar.timePill.showDate

            sourceComponent: Date {
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
