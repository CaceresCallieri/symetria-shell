pragma Singleton

import qs.components.misc
import qs.config
import Symmetria
import Symmetria.Internal
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property var toplevels: Hyprland.toplevels
    readonly property var workspaces: Hyprland.workspaces
    readonly property var monitors: Hyprland.monitors

    readonly property HyprlandToplevel activeToplevel: Hyprland.activeToplevel?.wayland?.activated ? Hyprland.activeToplevel : null
    readonly property HyprlandWorkspace focusedWorkspace: Hyprland.focusedWorkspace
    readonly property HyprlandMonitor focusedMonitor: Hyprland.focusedMonitor
    readonly property int activeWsId: focusedWorkspace?.id ?? 1

    readonly property HyprKeyboard keyboard: extras.devices.keyboards.find(kb => kb.main) ?? null
    readonly property bool capsLock: keyboard?.capsLock ?? false
    readonly property bool numLock: keyboard?.numLock ?? false
    readonly property string defaultKbLayout: keyboard?.layout.split(",")[0] ?? "??"
    readonly property string kbLayoutFull: keyboard?.activeKeymap ?? "Unknown"
    readonly property string kbLayout: kbMap.get(kbLayoutFull) ?? "??"
    readonly property var kbMap: new Map()

    readonly property alias extras: extras
    readonly property alias options: extras.options
    readonly property alias devices: extras.devices

    property bool hadKeyboard
    property string _lastUrgentAddr: ""
    property real _lastUrgentTime: 0
    property list<string> _pendingUrgentRetries: []

    signal configReloaded

    function dispatch(request: string): void {
        Hyprland.dispatch(request);
    }

    function monitorFor(screen: ShellScreen): HyprlandMonitor {
        return Hyprland.monitorFor(screen);
    }

    // ── Workspace lookup helpers ─────────────────────────────────────
    //
    // Single source of truth for the .find() lookups that previously lived
    // duplicated across Workspace.qml, MergedWorkspacePill.qml,
    // MergedBarContent.qml, and AgentService.qml. The Hyprland workspace
    // proxy returned by .find() is identity-unstable (a fresh object may
    // appear after refresh), so callers must continue to dereference it
    // each time rather than caching the object across frames.
    //
    // intentional var return: Hyprland workspace proxy is nullable and
    // identity-unstable, so it does not fit a stable QML type alias.
    function workspaceById(id: int): var {
        return Hyprland.workspaces.values.find(w => w.id === id) ?? null;
    }

    function workspaceByName(name: string): var {
        return Hyprland.workspaces.values.find(w => w.name === name) ?? null;
    }

    // Build the { [wsId]: hasWindows } occupancy map. Both the top-bar and
    // merged-bar parents (Workspaces.qml, MergedBarContent.qml) need this,
    // so it lives here to keep the .reduce() out of two places.
    function occupiedMap(): var {
        return Hyprland.workspaces.values.reduce((acc, w) => {
            acc[w.id] = w.lastIpcObject.windows > 0;
            return acc;
        }, {});
    }

    // Compute the sorted workspace ID list rendered in dynamic mode.
    // - includeSpecial: when true, appends special workspaces and sorts them last
    //   (used by the merged agentbar); when false, omits them entirely (top bar).
    // - activeWsId: ensured to appear even if empty, so the active slot never
    //   collapses out of the pill.
    //
    // Sort order: named (negative, non-special) → regular (positive) → special.
    // This matches both consumers; the simple ascending sort the top bar used
    // before is preserved because named (negative) IDs naturally precede
    // positive ones, and excludeSpecial keeps category-2 out.
    function displayedWorkspaceIds(includeSpecial: bool, activeWsId: int): var {
        const all = Hyprland.workspaces.values;
        const regularAndNamed = [];
        const specialWs = [];
        for (const w of all) {
            if (w.name.startsWith("special:"))
                specialWs.push(w);
            else
                regularAndNamed.push(w);
        }

        const occupiedWs = regularAndNamed.filter(w => w.lastIpcObject.windows > 0);
        const namedWsNames = Config.bar.workspaces.namedWorkspaceIcons.map(n => n.name);
        const namedWs = regularAndNamed.filter(w => namedWsNames.includes(w.name));

        let ids = [...new Set([...occupiedWs.map(w => w.id), ...namedWs.map(w => w.id)])];

        if (!ids.includes(activeWsId))
            ids.push(activeWsId);

        if (includeSpecial) {
            for (const sw of specialWs)
                ids.push(sw.id);
            ids = [...new Set(ids)];
        }

        const nameById = {};
        for (const w of all)
            nameById[w.id] = w.name;

        return ids.sort((a, b) => {
            const catA = _wsSortCategory(a, nameById[a] ?? "");
            const catB = _wsSortCategory(b, nameById[b] ?? "");
            if (catA !== catB)
                return catA - catB;
            return a - b;
        });
    }

    function _wsSortCategory(wsId: int, wsName: string): int {
        if (wsName.startsWith("special:"))
            return 2;
        if (wsId < 0)
            return 0;
        return 1;
    }

    function reloadDynamicConfs(): void {
        extras.batchMessage(["keyword bindlni ,Caps_Lock,global,symmetria:refreshDevices", "keyword bindlni ,Num_Lock,global,symmetria:refreshDevices"]);
    }

    function handleUrgent(addr: string): void {
        if (!Config.utilities.toasts.windowUrgent)
            return;

        const now = Date.now();
        if (addr === root._lastUrgentAddr && now - root._lastUrgentTime < 3000)
            return;
        // Update dedup state before resolution — throttles spam even across deferred retries.
        root._lastUrgentAddr = addr;
        root._lastUrgentTime = now;

        root._tryEmitUrgent(addr, false);
    }

    // Resolves the urgent window and emits a toast. If class resolution fails (common race:
    // urgent arrives before Hyprland's toplevels model has registered the new window, e.g. on
    // fresh terminal spawn), refresh the model and retry once after 250ms. Still unresolved →
    // drop silently, since an unidentified toast can't be click-focused meaningfully.
    function _tryEmitUrgent(addr: string, isRetry: bool): void {
        const fullAddr = "0x" + addr;

        // Suppress urgent raised by the currently focused window — you can already see it.
        // Use raw Hyprland.activeToplevel (not root.activeToplevel) to avoid the wayland-activation gate.
        const activeAddr = Hyprland.activeToplevel?.lastIpcObject?.address ?? "";
        if (activeAddr && activeAddr === fullAddr)
            return;

        let windowClass = "";
        let windowTitle = "";
        for (const toplevel of Hyprland.toplevels.values) {
            const ipc = toplevel.lastIpcObject;
            if (ipc && ipc.address === fullAddr) {
                windowClass = ipc.class ?? "";
                windowTitle = toplevel.title ?? "";
                break;
            }
        }

        if (!windowClass) {
            if (isRetry)
                return;
            Hyprland.refreshToplevels();
            if (!root._pendingUrgentRetries.includes(addr))
                root._pendingUrgentRetries.push(addr);
            urgentRetryTimer.restart();
            return;
        }

        // Class blocklist — suppress urgent from known offenders (e.g. Unreal Editor raising
        // attention on internal sub-window navigation).
        const blocklist = Config.utilities.toasts.windowUrgentBlocklist ?? [];
        if (blocklist.includes(windowClass))
            return;

        Toaster.toast(windowClass, windowTitle || qsTr("Window is requesting attention"), "notification_important", Toast.Warning, 7000, "", "", function () {
            root.dispatch(`focuswindow address:${fullAddr}`);
        });
    }

    Timer {
        id: urgentRetryTimer
        interval: 250
        repeat: false
        onTriggered: {
            const queue = root._pendingUrgentRetries;
            root._pendingUrgentRetries = [];
            for (const addr of queue)
                root._tryEmitUrgent(addr, true);
        }
    }

    Component.onCompleted: reloadDynamicConfs()

    onCapsLockChanged: {
        if (!Config.utilities.toasts.capsLockChanged)
            return;

        if (capsLock)
            Toaster.toast(qsTr("Caps lock enabled"), qsTr("Caps lock is currently enabled"), "keyboard_capslock_badge");
        else
            Toaster.toast(qsTr("Caps lock disabled"), qsTr("Caps lock is currently disabled"), "keyboard_capslock");
    }

    onNumLockChanged: {
        if (!Config.utilities.toasts.numLockChanged)
            return;

        if (numLock)
            Toaster.toast(qsTr("Num lock enabled"), qsTr("Num lock is currently enabled"), "looks_one");
        else
            Toaster.toast(qsTr("Num lock disabled"), qsTr("Num lock is currently disabled"), "timer_1");
    }

    onKbLayoutFullChanged: {
        if (hadKeyboard && Config.utilities.toasts.kbLayoutChanged)
            Toaster.toast(qsTr("Keyboard layout changed"), qsTr("Layout changed to: %1").arg(kbLayoutFull), "keyboard");

        hadKeyboard = !!keyboard;
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            const n = event.name;
            if (n.endsWith("v2"))
                return;

            if (n === "configreloaded") {
                root.configReloaded();
                root.reloadDynamicConfs();
            } else if (["workspace", "moveworkspace", "activespecial", "focusedmon"].includes(n)) {
                Hyprland.refreshWorkspaces();
                Hyprland.refreshMonitors();
            } else if (["openwindow", "closewindow", "movewindow"].includes(n)) {
                Hyprland.refreshToplevels();
                Hyprland.refreshWorkspaces();
            } else if (n === "urgent") {
                root.handleUrgent(event.data);
                return;
            } else if (n.includes("mon")) {
                Hyprland.refreshMonitors();
            } else if (n.includes("workspace")) {
                Hyprland.refreshWorkspaces();
            } else if (n.includes("window") || n.includes("group") || ["pin", "fullscreen", "changefloatingmode", "minimize"].includes(n)) {
                Hyprland.refreshToplevels();
            }
        }
    }

    FileView {
        id: kbLayoutFile

        path: Quickshell.env("SYMMETRIA_XKB_RULES_PATH") || "/usr/share/X11/xkb/rules/base.lst"
        onLoaded: {
            const layoutMatch = text().match(/! layout\n([\s\S]*?)\n\n/);
            if (layoutMatch) {
                const lines = layoutMatch[1].split("\n");
                for (const line of lines) {
                    if (!line.trim() || line.trim().startsWith("!"))
                        continue;

                    const match = line.match(/^\s*([a-z]{2,})\s+([a-zA-Z() ]+)$/);
                    if (match)
                        root.kbMap.set(match[2], match[1]);
                }
            }

            const variantMatch = text().match(/! variant\n([\s\S]*?)\n\n/);
            if (variantMatch) {
                const lines = variantMatch[1].split("\n");
                for (const line of lines) {
                    if (!line.trim() || line.trim().startsWith("!"))
                        continue;

                    const match = line.match(/^\s*([a-zA-Z0-9_-]+)\s+([a-z]{2,}): (.+)$/);
                    if (match)
                        root.kbMap.set(match[3], match[2]);
                }
            }
        }
    }

    IpcHandler {
        target: "hypr"

        function refreshDevices(): void {
            extras.refreshDevices();
        }
    }

    CustomShortcut {
        name: "refreshDevices"
        description: "Reload devices"
        onPressed: extras.refreshDevices()
        onReleased: extras.refreshDevices()
    }

    HyprExtras {
        id: extras
    }
}
