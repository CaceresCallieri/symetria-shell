import qs.components.misc
import qs.modules.controlcenter
import qs.services
import qs.config
import Symmetria
import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    property bool launcherInterrupted
    readonly property bool hasFullscreen: Hypr.focusedWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen === 2) ?? false

    // For delayed drawer switching (launcher <-> clipboard mutual exclusion)
    property string pendingDrawer: ""

    // Timer for delayed drawer opening after close animation completes.
    // Duration must match the hide animation in drawers/Wrapper.qml.
    // Using restart() ensures rapid toggling honors only the final request.
    Timer {
        id: drawerSwitchTimer
        interval: Appearance.anim.durations.normal
        onTriggered: {
            if (root.pendingDrawer) {
                const visibilities = Visibilities.getForActive();
                visibilities[root.pendingDrawer] = true;
                root.pendingDrawer = "";
            }
        }
    }

    // Toggles a drawer with mutual exclusion against an opposite drawer.
    // If the opposite drawer is open, closes it first and delays opening.
    function toggleDrawerWithExclusion(drawerName: string, oppositeDrawerName: string): void {
        const visibilities = Visibilities.getForActive();

        // If this drawer is already pending, cancel the pending open
        if (root.pendingDrawer === drawerName) {
            root.pendingDrawer = "";
            drawerSwitchTimer.stop();
            return;
        }

        if (!visibilities[drawerName]) {
            // Opening drawer
            if (visibilities[oppositeDrawerName]) {
                // Opposite is open - close it and delay this drawer
                visibilities[oppositeDrawerName] = false;
                root.pendingDrawer = drawerName;
                drawerSwitchTimer.restart();
            } else {
                // Opposite not open - open immediately
                root.pendingDrawer = "";
                drawerSwitchTimer.stop();
                visibilities[drawerName] = true;
            }
        } else {
            // Closing drawer - cancel any pending switch
            root.pendingDrawer = "";
            drawerSwitchTimer.stop();
            visibilities[drawerName] = false;
        }
    }

    CustomShortcut {
        name: "controlCenter"
        description: "Open control center"
        onPressed: WindowFactory.create()
    }

    CustomShortcut {
        name: "showall"
        description: "Toggle launcher, dashboard and osd"
        onPressed: {
            if (root.hasFullscreen)
                return;
            const v = Visibilities.getForActive();
            v.launcher = v.dashboard = v.osd = v.utilities = !(v.launcher || v.dashboard || v.osd || v.utilities);
        }
    }

    CustomShortcut {
        name: "dashboard"
        description: "Toggle dashboard"
        onPressed: {
            if (root.hasFullscreen)
                return;
            const visibilities = Visibilities.getForActive();
            visibilities.dashboard = !visibilities.dashboard;
        }
    }

    CustomShortcut {
        name: "session"
        description: "Toggle session menu"
        onPressed: {
            if (root.hasFullscreen)
                return;
            const visibilities = Visibilities.getForActive();
            visibilities.session = !visibilities.session;
        }
    }

    CustomShortcut {
        name: "launcher"
        description: "Toggle launcher"
        onPressed: root.launcherInterrupted = false
        onReleased: {
            if (!root.launcherInterrupted && !root.hasFullscreen)
                toggleDrawerWithExclusion("launcher", "clipboard");
            root.launcherInterrupted = false;
        }
    }

    CustomShortcut {
        name: "launcherInterrupt"
        description: "Interrupt launcher keybind"
        onPressed: root.launcherInterrupted = true
    }

    CustomShortcut {
        name: "clipboard"
        description: "Toggle clipboard history"
        onReleased: {
            if (!root.hasFullscreen)
                toggleDrawerWithExclusion("clipboard", "launcher");
        }
    }

    IpcHandler {
        target: "drawers"

        function toggle(drawer: string): void {
            if (list().split("\n").includes(drawer)) {
                if (root.hasFullscreen && ["launcher", "session", "dashboard", "clipboard"].includes(drawer))
                    return;

                // Mutual exclusion for launcher <-> clipboard
                if (drawer === "launcher")
                    toggleDrawerWithExclusion("launcher", "clipboard");
                else if (drawer === "clipboard")
                    toggleDrawerWithExclusion("clipboard", "launcher");
                else
                    Visibilities.getForActive()[drawer] = !Visibilities.getForActive()[drawer];
            } else {
                console.warn(`[IPC] Drawer "${drawer}" does not exist`);
            }
        }

        function list(): string {
            const visibilities = Visibilities.getForActive();
            return Object.keys(visibilities).filter(k => typeof visibilities[k] === "boolean").join("\n");
        }
    }

    IpcHandler {
        target: "controlCenter"

        function open(): void {
            WindowFactory.create();
        }
    }

    IpcHandler {
        target: "toaster"

        function info(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Info);
        }

        function success(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Success);
        }

        function warn(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Warning);
        }

        function error(title: string, message: string, icon: string): void {
            Toaster.toast(title, message, icon, Toast.Error);
        }
    }
}
