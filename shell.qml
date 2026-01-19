//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

import "modules"
import "modules/drawers"
import "modules/background"
import "modules/areapicker"
import "modules/lock"
import "modules/askpass"
import Quickshell
import QtQuick

ShellRoot {
    // Disable hot reload - deferred to avoid "Non-existent attached object" error
    Timer {
        interval: 0
        running: true
        onTriggered: Quickshell.watchFiles = false
    }

    Background {}
    Drawers {}
    AreaPicker {}
    Askpass {}
    Lock {
        id: lock
    }

    Shortcuts {}
    BatteryMonitor {}
    IdleMonitors {
        lock: lock
    }
}
