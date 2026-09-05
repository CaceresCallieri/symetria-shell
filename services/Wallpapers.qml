pragma Singleton

import qs.config
import qs.utils
import Symmetria
import Symmetria.FileManager.Models
import Quickshell
import Quickshell.Io
import QtQuick

Searcher {
    id: root

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    // Not initialized from file - remains empty until setWallpaper() is called.
    // Fallback logic uses workspace wallpapers or shows "missing wallpaper" UI.
    property string actualCurrent
    property bool focusMode: false
    readonly property bool wallpaperVisible: !focusMode

    // Texture-load gate distinct from wallpaperVisible: stays TRUE during fade-out
    // so the GPU texture survives the opacity animation, then flips FALSE so the
    // CachingImage source is cleared and the texture is dropped. Re-enabled
    // immediately when focus mode turns off so Qt can async-load before the
    // fade-in starts. See modules/background/Wallpaper.qml for the consumer.
    //
    // Managed imperatively by onFocusModeChanged and FileView.onLoaded — NOT a
    // live binding. Initial value is true (focusMode defaults false; onLoaded
    // corrects it synchronously before the first frame if restored from disk).
    property bool wallpaperLoaded: true

    // Buffer beyond Appearance.anim.durations.normal to guarantee the wrapper
    // Item opacity reaches 0 before we drop the texture. Bound to the actual
    // animation duration so custom anim.scale values (e.g. scale=2 for slow
    // motion / accessibility) don't cause the texture to pop mid-fade.
    Timer {
        id: focusUnloadTimer
        interval: Appearance.anim.durations.normal + 50
        onTriggered: root.wallpaperLoaded = false
    }

    // Flag suppresses the "focus mode toggled" toast during the initial load
    // from disk — otherwise the user would see a stale toast every shell restart.
    property bool _focusModeLoadedFromDisk: false

    onFocusModeChanged: {
        // Persist immediately (debounced save fires after a short delay)
        if (_focusModeLoadedFromDisk)
            focusModeSaveTimer.restart();

        // Load/unload texture coordination
        if (focusMode) {
            focusUnloadTimer.restart();  // delay unload until fade-out completes
        } else {
            focusUnloadTimer.stop();
            wallpaperLoaded = true;  // begin reload immediately, fade-in follows
        }

        // User-facing toast (skip on the initial restoration from disk)
        if (!_focusModeLoadedFromDisk)
            return;
        if (!Config.utilities.toasts.focusModeChanged)
            return;
        // One shared key for both states: rapid toggles UPDATE the existing
        // toast in place instead of stacking one toast per toggle.
        if (focusMode)
            Toaster.toast(qsTr("Focus mode"), qsTr("Wallpaper hidden"), "visibility_off", Toast.Info, 0, "", "focus-mode");
        else
            Toaster.toast(qsTr("Focus mode off"), qsTr("Wallpaper restored"), "visibility", Toast.Info, 0, "", "focus-mode");
    }

    // Debounced save to avoid hammering disk if the user toggles rapidly.
    Timer {
        id: focusModeSaveTimer
        interval: 250
        onTriggered: focusStateFile.setText(JSON.stringify({
            focusMode: root.focusMode
        }))
    }

    FileView {
        id: focusStateFile

        path: `${Paths.state}/wallpaper-state.json`
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (typeof data.focusMode === "boolean")
                    root.focusMode = data.focusMode;
            } catch (e) {
                console.warn("[Wallpapers] Failed to parse wallpaper-state.json:", e);
            }
            // wallpaperLoaded must mirror the restored focusMode synchronously —
            // onFocusModeChanged would have started focusUnloadTimer (for the focus=true
            // case) before we could correct wallpaperLoaded here. Stop it now: we've
            // already applied the correct value directly, no deferred unload needed.
            root.wallpaperLoaded = !root.focusMode;
            focusUnloadTimer.stop();
            root._focusModeLoadedFromDisk = true;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                setText(JSON.stringify({
                    focusMode: false
                }));
                root._focusModeLoadedFromDisk = true;
            } else {
                // Non-FileNotFound errors (permission denied, IO error, etc.) must still
                // set the flag so toasts and disk saves work for the rest of the session.
                console.warn("[Wallpapers] Failed to load wallpaper-state.json:", err);
                root._focusModeLoadedFromDisk = true;
            }
        }
    }

    // Per-workspace wallpaper support
    readonly property string workspaceWallpaperDir: `${Paths.wallsdir}/${Config.background.perWorkspaceWallpapers.directory}`
    property var workspaceWallpaperMap: ({})
    property int workspaceMapVersion: 0  // Incremented to force binding updates

    // Race condition guard: FileSystemModel scans directories asynchronously, so
    // Component.onCompleted fires before entries are populated. This flag ensures
    // the empty-directory check runs exactly once via either onEntriesChanged
    // (normal case) or the fallback timer (empty/missing directory case).
    property bool _workspaceCheckDone: false
    readonly property int _workspaceCheckTimeoutMs: 500

    // Validates workspace wallpaper directory after FileSystemModel scan completes.
    // Called by both onEntriesChanged (happy path) and fallback timer (empty dir).
    // Note: FileSystemModel doesn't emit entriesChanged when directory is empty/missing
    // because its C++ applyChanges() returns early when oldPaths == newPaths (both empty).
    function _checkWorkspaceWallpapers(): void {
        if (_workspaceCheckDone)
            return;
        _workspaceCheckDone = true;
        workspaceCheckTimer.stop();

        if (Config.background.perWorkspaceWallpapers.enabled && workspaceWallpapers.entries.length === 0) {
            console.warn(`Per-workspace wallpapers enabled but directory is empty or missing: ${workspaceWallpaperDir}`);
        }
    }

    function getWallpaperForWorkspace(workspaceId: int, workspaceName: string): string {
        if (!Config.background.perWorkspaceWallpapers.enabled)
            return actualCurrent;

        // Special workspaces (name starts with "special:") always use the global wallpaper.
        // Named workspaces also have negative IDs but should NOT be filtered here.
        if (workspaceName.startsWith("special:"))
            return actualCurrent;

        // Named workspaces: use the name as lookup key
        // Numbered workspaces: use the ID as lookup key
        const isNamedWorkspace = workspaceId <= 0 || workspaceName !== workspaceId.toString();
        const key = isNamedWorkspace ? workspaceName.toLowerCase() : workspaceId.toString();

        const mapped = workspaceWallpaperMap[key];

        if (mapped)
            return mapped;

        // Fallback behavior
        switch (Config.background.perWorkspaceWallpapers.fallbackBehavior) {
        case "global":
            return actualCurrent;
        case "first":
            return workspaceWallpapers.entries[0]?.path ?? actualCurrent;
        case "none":
            return "";
        default:
            return actualCurrent;
        }
    }

    function rebuildWorkspaceMap(): void {
        const newMap = {};
        const entries = workspaceWallpapers.entries;
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i];
            const name = entry.baseName;

            // Fix 3: Numeric match requires content after dash and wsId > 0
            const numMatch = name.match(/^(\d+)-(.+)/);
            if (numMatch && numMatch[2]) {
                const wsId = parseInt(numMatch[1], 10);
                if (wsId > 0) {
                    const key = wsId.toString();
                    if (newMap[key]) {
                        console.warn(`Duplicate workspace wallpaper for workspace ${wsId}: "${name}" (using "${newMap[key]}")`);
                    } else {
                        newMap[key] = entry.path;
                    }
                }
                continue;
            }

            // Fix 3: Named match requires content after dash
            const namedMatch = name.match(/^([A-Za-z]+)-(.+)/);
            if (namedMatch && namedMatch[2]) {
                const wsName = namedMatch[1].toLowerCase();
                if (newMap[wsName]) {
                    console.warn(`Duplicate workspace wallpaper for "${wsName}": "${name}" (using "${newMap[wsName]}")`);
                } else {
                    newMap[wsName] = entry.path;
                }
            }
        }
        workspaceWallpaperMap = newMap;
        workspaceMapVersion++;
    }

    // Build workspace map after component initialization (Qt.callLater ensures all properties are ready)
    Component.onCompleted: {
        Qt.callLater(() => {
            rebuildWorkspaceMap();
        });
    }

    function setWallpaper(path: string): void {
        actualCurrent = path;
        Quickshell.execDetached(["symmetria", "wallpaper", "-f", path]);
    }

    function preview(path: string): void {
        previewPath = path;
        showPreview = true;
    }

    function stopPreview(): void {
        showPreview = false;
    }

    list: wallpapers.entries
    key: "relativePath"
    useFuzzy: Config.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    IpcHandler {
        target: "wallpaper"

        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }

        function toggleFocus(): void {
            root.focusMode = !root.focusMode;
        }

        function focus(): void {
            root.focusMode = true;
        }

        function unfocus(): void {
            root.focusMode = false;
        }

        function isFocused(): bool {
            return root.focusMode;
        }
    }

    FileSystemModel {
        id: wallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Images
    }

    FileSystemModel {
        id: workspaceWallpapers

        recursive: false
        path: root.workspaceWallpaperDir
        filter: FileSystemModel.Images
        watchChanges: true
        onEntriesChanged: {
            root.rebuildWorkspaceMap();
            root._checkWorkspaceWallpapers();
        }
    }

    // Fallback timer for empty/missing directories where FileSystemModel's entriesChanged
    // doesn't fire (oldPaths == newPaths in C++ applyChanges causes early return)
    Timer {
        id: workspaceCheckTimer
        interval: root._workspaceCheckTimeoutMs
        repeat: false
        running: Config.background.perWorkspaceWallpapers.enabled && !root._workspaceCheckDone
        onTriggered: root._checkWorkspaceWallpapers()
    }
}
