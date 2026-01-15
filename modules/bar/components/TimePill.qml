pragma ComponentBehavior: Bound

import qs.components
import qs.services
import qs.config
import QtQuick
import QtQuick.Layouts

StyledRect {
    id: root

    // Use tertiary color for time/system info pills (vs secondary for status icons)
    // This provides visual distinction between different functional pill groups
    property color colour: Colours.palette.m3tertiary

    // Popout interface for calendar popout (planned feature)
    // Child components expose 'name' property for detectChildPopout() integration
    readonly property alias iconContainer: content

    // Note: Child components (Clock, Date) may display icons based on Config.bar.clock.showIcon
    // and Config.bar.date.showIcon respectively. When both are shown, this creates an
    // icon-time-icon-date pattern which is intentional for visual identification.

    // Glassmorphism styling (subtle intensity for background containers,
    // matching StatusIcons and Tray pill styling)
    readonly property var glassStyle: Colours.glassmorphism(
        Colours.palette.m3surfaceContainerHigh,
        Colours.glass.subtle
    )

    color: glassStyle.background
    radius: Appearance.rounding.full
    border.width: 1
    border.color: glassStyle.border

    // Internal padding for the pill (left and right edges)
    readonly property int pillPadding: Appearance.spacing.large

    clip: true
    implicitHeight: Config.bar.sizes.innerWidth
    implicitWidth: content.implicitWidth

    // Hide entirely when no items are visible
    visible: Config.bar.timePill.showClock || Config.bar.timePill.showDate

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
        WrappedLoader {
            name: "clock"
            active: Config.bar.timePill.showClock

            sourceComponent: Clock {
                colour: root.colour
            }
        }

        // Date
        WrappedLoader {
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

    Behavior on implicitWidth {
        Anim {}
    }

    component WrappedLoader: Loader {
        required property string name

        Layout.alignment: Qt.AlignVCenter
        asynchronous: true
        visible: active
    }
}
