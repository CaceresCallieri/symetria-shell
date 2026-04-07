//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env QT_QPA_PLATFORM=wayland

import "modules"
import "modules/drawers" as DrawersModule
import "modules/background" as BackgroundModule
import "modules/areapicker" as AreaPickerModule
import "modules/osd" as OsdModule
import "modules/notifications" as NotifsModule
import "modules/lock"
import "modules/askpass"
import "modules/stt"
import "modules/keycaster"
import "modules/keychords" as KeyChordsModule
import "modules/killconfirm" as KillConfirmModule
import Quickshell
import QtQuick

ShellRoot {
    // Disable hot reload - deferred to avoid "Non-existent attached object" error
    Timer {
        interval: 0
        running: true
        onTriggered: Quickshell.watchFiles = false
    }

    BackgroundModule.Wrapper {}
    DrawersModule.Wrapper {}
    AreaPickerModule.Wrapper {}
    OsdModule.OsdOverlay {}
    NotifsModule.NotificationsOverlay {}
    Askpass {}
    Stt {}
    Keycaster {}
    KeyChordsModule.Wrapper {}
    KeyChordsModule.KeyChordsOverlay {}
    KillConfirmModule.Wrapper {
        id: killConfirm
    }
    KillConfirmModule.KillConfirmOverlay {
        handler: killConfirm
    }
    Lock {
        id: lock
    }

    Shortcuts {}
    BatteryMonitor {}
    IdleMonitors {
        lock: lock
    }
}
