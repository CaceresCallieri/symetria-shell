pragma ComponentBehavior: Bound

import qs.modules.dashboard.dash as Dash
import qs.config
import QtQuick

Item {
    id: root

    width: Config.bar.sizes.calendarWidth

    QtObject {
        id: calendarState
        property date currentDate: new Date()
    }

    Dash.Calendar {
        id: calendar

        state: calendarState
    }

    implicitWidth: Config.bar.sizes.calendarWidth
    implicitHeight: calendar.implicitHeight
}
