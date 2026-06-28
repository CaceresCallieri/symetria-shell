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
import "modules/session" as SessionModule
import "modules/toasts" as ToastsModule
import "modules/lock"
import "modules/askpass"
import "modules/recorder"
import "modules/keycaster"
import "modules/keychords" as KeyChordsModule
import "modules/killconfirm" as KillConfirmModule
import "modules/windowoverview" as WindowOverviewModule
import "modules/agentoverview" as AgentOverviewModule
import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    // Disable hot reload - deferred to avoid "Non-existent attached object" error
    Timer {
        interval: 0
        running: true
        onTriggered: Quickshell.watchFiles = false
    }

    // Kill competing notification daemons (swaync, dunst, mako) so QuickShell can
    // claim org.freedesktop.Notifications. DBus activation files auto-start these
    // even when their systemd services are disabled. QuickShell's NotificationServer
    // watches for the name to become available and re-registers automatically.
    Process {
        running: true
        command: ["sh", "-c", "pkill -x swaync; pkill -x dunst; pkill -x mako; exit 0"]
    }

    BackgroundModule.Wrapper {}
    DrawersModule.Wrapper {}
    AreaPickerModule.Wrapper {}
    OsdModule.OsdOverlay {}
    NotifsModule.NotificationsOverlay {}
    SessionModule.SessionOverlay {}
    ToastsModule.ToastsOverlay {}
    Askpass {}
    RecorderRoot {}
    Keycaster {}
    KeyChordsModule.Wrapper {}
    KeyChordsModule.KeyChordsOverlay {}
    KillConfirmModule.Wrapper {
        id: killConfirm
    }
    KillConfirmModule.KillConfirmOverlay {
        handler: killConfirm
    }
    WindowOverviewModule.Wrapper {}
    WindowOverviewModule.OverviewSurface {}
    AgentOverviewModule.Wrapper {}
    AgentOverviewModule.OverviewSurface {}
    Lock {
        id: lock
    }

    Shortcuts {}
    BatteryMonitor {}
    IdleMonitors {
        lock: lock
    }
}
