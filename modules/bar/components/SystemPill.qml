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
        WrappedLoader {
            name: "cpu"
            active: Config.bar.systemPill.showCpu

            sourceComponent: CpuStatus {
                colour: root.colour
            }
        }

        // RAM Usage
        WrappedLoader {
            name: "ram"
            active: Config.bar.systemPill.showRam

            sourceComponent: RamUsage {
                colour: root.colour
            }
        }

        // Available Updates
        WrappedLoader {
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
