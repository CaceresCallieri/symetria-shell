//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env QT_QPA_PLATFORM=wayland

import "modules"
import "modules/drawers"
import "modules/background"
import "modules/areapicker"
import "modules/osd" as OsdModule
import "modules/notifications" as NotifsModule
import "modules/lock"
import "modules/askpass"
import "modules/stt"
import "modules/keycaster"
import "modules/keychords"
import "modules/keychords" as KeyChordsModule
import "modules/killconfirm"
import Quickshell
import QtQuick

ShellRoot {
    // ── Startup profiler (temporary) ──────────────────────────────
    // Measures event loop freeze duration. Beat #1 at +500ms = instant.
    // Beat #1 at +Ns = event loop was frozen for (N - 500)ms.
    // Remove after measurement session.
    Component.onCompleted: console.log("[BOOT] ShellRoot @ " + Date.now())
    Timer {
        interval: 500; running: true; repeat: true; property int b: 0
        onTriggered: {
            b++;
            console.log("[BOOT:HB] #" + b + " @ " + Date.now());
            if (b >= 20) running = false;
        }
    }
    // ──────────────────────────────────────────────────────────────

    // Disable hot reload - deferred to avoid "Non-existent attached object" error
    Timer {
        interval: 0
        running: true
        onTriggered: Quickshell.watchFiles = false
    }

    Background {}
    Drawers {}
    AreaPicker {}
    OsdModule.OsdOverlay {}
    NotifsModule.NotificationsOverlay {}
    Askpass {}
    Stt {}
    Keycaster {}
    KeyChords {}
    KeyChordsModule.KeyChordsOverlay {}
    KillConfirm {
        id: killConfirm
    }
    KillConfirmOverlay {
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
