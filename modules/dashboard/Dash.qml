import qs.components
import qs.components.filedialog
import qs.services
import qs.config
import "dash"
import Quickshell
import QtQuick
import QtQuick.Layouts

GridLayout {
    id: root

    required property PersistentProperties visibilities
    required property PersistentProperties state
    required property FileDialog facePicker

    rowSpacing: Appearance.spacing.normal
    columnSpacing: Appearance.spacing.normal

    Rect {
        Layout.row: 2
        Layout.column: 0
        Layout.columnSpan: 5
        Layout.fillWidth: true
        Layout.preferredHeight: user.implicitHeight

        radius: Appearance.rounding.large

        User {
            id: user

            visibilities: root.visibilities
            state: root.state
            facePicker: root.facePicker
        }
    }

    Rect {
        Layout.row: 0
        Layout.column: 0
        Layout.columnSpan: 2
        Layout.preferredWidth: Config.dashboard.sizes.weatherWidth
        Layout.preferredHeight: weather.implicitHeight

        radius: Appearance.rounding.large * 1.5

        Weather {
            id: weather
        }
    }

    Rect {
        Layout.row: 1
        Layout.column: 0
        Layout.preferredWidth: dateTime.implicitWidth
        Layout.fillHeight: true

        radius: Appearance.rounding.normal

        DateTime {
            id: dateTime
        }
    }

    Rect {
        Layout.row: 1
        Layout.column: 1
        Layout.columnSpan: 3
        Layout.fillWidth: true
        Layout.minimumWidth: calendar.implicitWidth
        Layout.preferredHeight: calendar.implicitHeight

        radius: Appearance.rounding.large

        Calendar {
            id: calendar

            state: root.state
        }
    }

    Rect {
        Layout.row: 1
        Layout.column: 4
        Layout.preferredWidth: resources.implicitWidth
        Layout.fillHeight: true

        radius: Appearance.rounding.normal

        Resources {
            id: resources
        }
    }

    Rect {
        Layout.row: 0
        Layout.column: 5
        Layout.rowSpan: 3
        Layout.preferredWidth: media.implicitWidth
        Layout.fillHeight: true

        radius: Appearance.rounding.large * 2

        Media {
            id: media
        }
    }

    component Rect: StyledRect {
        color: Colours.palette.m3surfaceContainer
    }
}
