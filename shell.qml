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
import Quickshell
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: shellRoot

    Component.onCompleted: console.log("[BOOT] ShellRoot.onCompleted @ " + Date.now())

    // Disable hot reload - deferred to avoid "Non-existent attached object" error
    Timer {
        interval: 0
        running: true
        onTriggered: Quickshell.watchFiles = false
    }

    // BOOT PROFILER: heartbeat to detect event loop freezes
    Timer {
        id: bootHeartbeat
        interval: 500
        running: true
        repeat: true
        property int beats: 0
        onTriggered: {
            beats++;
            console.log("[BOOT:HEARTBEAT] beat #" + beats + " @ " + Date.now());
            if (beats >= 60) running = false;
        }
    }

    // BOOT PROFILER: Single minimal PanelWindow test
    // Background { Component.onCompleted: console.log("[BOOT] Background module created @ " + Date.now()) }
    // Drawers { Component.onCompleted: console.log("[BOOT] Drawers module created @ " + Date.now()) }

    // BOOT PROFILER: Testing Drawers with Exclusion zones disabled
    Drawers { Component.onCompleted: console.log("[BOOT] Drawers module created @ " + Date.now()) }
    // AreaPicker { Component.onCompleted: console.log("[BOOT] AreaPicker module created @ " + Date.now()) }
    // OsdModule.OsdOverlay { Component.onCompleted: console.log("[BOOT] OsdOverlay module created @ " + Date.now()) }
    // NotifsModule.NotificationsOverlay { Component.onCompleted: console.log("[BOOT] NotificationsOverlay module created @ " + Date.now()) }
    // Askpass { Component.onCompleted: console.log("[BOOT] Askpass module created @ " + Date.now()) }
    // Stt { Component.onCompleted: console.log("[BOOT] Stt module created @ " + Date.now()) }
    // Keycaster { Component.onCompleted: console.log("[BOOT] Keycaster module created @ " + Date.now()) }
    // KeyChords { Component.onCompleted: console.log("[BOOT] KeyChords module created @ " + Date.now()) }
    Lock {
        id: lock
        Component.onCompleted: console.log("[BOOT] Lock module created @ " + Date.now())
    }

    // Shortcuts { Component.onCompleted: console.log("[BOOT] Shortcuts module created @ " + Date.now()) }
    // BatteryMonitor { Component.onCompleted: console.log("[BOOT] BatteryMonitor module created @ " + Date.now()) }
    IdleMonitors {
        lock: lock
        Component.onCompleted: console.log("[BOOT] IdleMonitors module created @ " + Date.now())
    }
}
