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

    // Opens calculator with exclusive access - closes launcher/clipboard if open
    function openCalculatorExclusive(): void {
        const visibilities = Visibilities.getForActive();
        if (visibilities.launcher)
            visibilities.launcher = false;
        if (visibilities.clipboard)
            visibilities.clipboard = false;
        visibilities.calculator = !visibilities.calculator;
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

    function activeShellScreen(): var {
        for (const screen of Visibilities.popouts.keys()) {
            if (Hypr.monitorFor(screen) === Hypr.focusedMonitor)
                return screen;
        }
        return null;
    }

    function toggleWirelessPopout(): void {
        const screen = activeShellScreen();
        const popout = screen ? Visibilities.popouts.get(screen) : null;
        if (!popout) {
            console.warn("[WirelessShortcut] No popout is registered for the focused monitor");
            return;
        }

        if (popout.keyboardNavigationActive && popout.hasCurrent) {
            popout.close();
            return;
        }

        popout.keyboardNavigationActive = true;
        const bar = Visibilities.bars.get(screen);
        if (!bar?.openNamedPopout("network")) {
            // The network indicator can be hidden by configuration. Keep the
            // keyboard entry point usable and center the popout in that case.
            popout.currentName = "network";
            popout.currentCenter = screen.width / 2;
            popout.hasCurrent = true;
        }
    }

    CustomShortcut {
        name: "controlCenter"
        description: "Open control center"
        onPressed: WindowFactory.create()
    }

    CustomShortcut {
        name: "showall"
        description: "Toggle launcher, OSD overlay, and utilities"
        onPressed: {
            if (root.hasFullscreen)
                return;
            const v = Visibilities.getForActive();
            const overlay = Visibilities.osdOverlays.get(Hypr.focusedMonitor);
            const anyShowing = v.launcher || v.utilities || (overlay?.showing ?? false);
            const show = !anyShowing;
            v.launcher = v.utilities = show;
            if (show)
                overlay?.show();
            else
                overlay?.hide();
        }
    }

    // DISABLED: Dashboard is disabled and slated for removal.
    // To re-enable: set Config.dashboard.enabled to true in shell.json and uncomment below.
    // CustomShortcut {
    //     name: "dashboard"
    //     description: "Toggle dashboard"
    //     onPressed: { ... }
    // }

    CustomShortcut {
        name: "session"
        description: "Toggle session menu"
        onPressed: {
            // Session menu renders on WlrLayer.Overlay (SessionOverlay.qml),
            // so it works above fullscreen clients — no hasFullscreen guard.
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

    CustomShortcut {
        name: "calculator"
        description: "Toggle calculator"
        onReleased: {
            if (!root.hasFullscreen)
                openCalculatorExclusive();
        }
    }

    IpcHandler {
        target: "drawers"

        function toggle(drawer: string): void {
            // OSD is no longer a drawer — route to overlay
            if (drawer === "osd") {
                const overlay = Visibilities.osdOverlays.get(Hypr.focusedMonitor);
                if (overlay)
                    overlay.toggle();
                else
                    console.warn("[IPC] OSD overlay not available");
                return;
            }

            if (list().split("\n").includes(drawer)) {
                // session is omitted — its overlay is on WlrLayer.Overlay and
                // remains usable above fullscreen clients.
                if (root.hasFullscreen && ["launcher", "clipboard", "calculator", "packages"].includes(drawer))
                    return;

                // Mutual exclusion for launcher <-> clipboard
                if (drawer === "launcher")
                    toggleDrawerWithExclusion("launcher", "clipboard");
                else if (drawer === "clipboard")
                    toggleDrawerWithExclusion("clipboard", "launcher");
                else if (drawer === "calculator")
                    openCalculatorExclusive();
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
        target: "wifi"

        function toggle(): void {
            root.toggleWirelessPopout();
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

        // Keyed variants: update an existing toast with matching key in-place, or create a new one.
        // infoKeyed uses timeout=-1 (persistent) so the loading toast stays visible until the
        // follow-up successKeyed/errorKeyed call explicitly replaces it.
        // successKeyed/warnKeyed/errorKeyed use timeout=0 (type-default auto-close).
        function infoKeyed(title: string, message: string, icon: string, key: string): void {
            Toaster.toast(title, message, icon, Toast.Info, -1, "", key);
        }

        function successKeyed(title: string, message: string, icon: string, key: string): void {
            Toaster.toast(title, message, icon, Toast.Success, 0, "", key);
        }

        function warnKeyed(title: string, message: string, icon: string, key: string): void {
            Toaster.toast(title, message, icon, Toast.Warning, 0, "", key);
        }

        function errorKeyed(title: string, message: string, icon: string, key: string): void {
            Toaster.toast(title, message, icon, Toast.Error, 0, "", key);
        }

        // IPC entrypoint: symmetria shell toaster infoImage <title> <message> <icon> <imagePath>
        function infoImage(title: string, message: string, icon: string, imagePath: string): void {
            Toaster.toast(title, message, icon, Toast.Info, 5000, imagePath);
        }
    }

    // Surface design language — two orthogonal axes. Switching is live.
    //   symmetria shell surface material metal    (clay | metal)
    //   symmetria shell surface form panel        (islands | panel)
    //   symmetria shell surface toggleMaterial
    //   symmetria shell surface toggleForm
    //   symmetria shell surface get
    //   symmetria shell surface list
    //
    // Target is "surface", NOT "theme": services/Colours.qml already registers a
    // "theme" handler (the palette dump). Quickshell silently drops the SECOND
    // handler registered for a target — it logs "Handler was registered but will
    // not be used" and the IPC call then fails with no obvious cause. "surface"
    // is also the more accurate name: this selects the surface design language,
    // while Colours' "theme" is about the colour palette.
    IpcHandler {
        target: "surface"

        function material(name: string): void {
            if (!Theme.isValidMaterial(name)) {
                console.warn(`[IPC] Unknown material "${name}". Available: ${Theme.materials.join(", ")}`);
                return;
            }
            Theme.material = name;
        }

        function form(name: string): void {
            if (!Theme.isValidForm(name)) {
                console.warn(`[IPC] Unknown form "${name}". Available: ${Theme.forms.join(", ")}`);
                return;
            }
            Theme.form = name;
        }

        function toggleMaterial(): void {
            Theme.cycleMaterial();
        }

        function toggleForm(): void {
            Theme.cycleForm();
        }

        function get(): string {
            return `${Theme.material} / ${Theme.form}`;
        }

        function list(): string {
            return `materials: ${Theme.materials.join(", ")}\nforms: ${Theme.forms.join(", ")}`;
        }
    }
}
