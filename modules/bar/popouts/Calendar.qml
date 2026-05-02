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
        // Frame the navigation header and calendar body in claymorphism
        // PillCards. The dashboard keeps panelMode: false because it has its
        // own outer Rect frame.
        panelMode: true
    }

    implicitWidth: Config.bar.sizes.calendarWidth
    implicitHeight: calendar.implicitHeight
}
