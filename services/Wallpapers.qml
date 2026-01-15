pragma Singleton

import qs.config
import qs.utils
import Caelestia.Models
import Quickshell
import Quickshell.Io
import QtQuick

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: Config.services.smartScheme ? [] : ["--no-smart"]

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property bool previewColourLock

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
        if (_workspaceCheckDone) return;
        _workspaceCheckDone = true;
        workspaceCheckTimer.stop();

        if (Config.background.perWorkspaceWallpapers.enabled && workspaceWallpapers.entries.length === 0) {
            console.warn(`Per-workspace wallpapers enabled but directory is empty or missing: ${workspaceWallpaperDir}`);
        }
    }

    function getWallpaperForWorkspace(workspaceId: int, workspaceName: string): string {
        if (!Config.background.perWorkspaceWallpapers.enabled)
            return actualCurrent;

        // Fix 5: Special workspaces (negative IDs) use global wallpaper
        if (workspaceId < 0)
            return actualCurrent;

        const key = workspaceId > 0 ? workspaceId.toString() : workspaceName.toLowerCase();
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
        Quickshell.execDetached(["caelestia", "wallpaper", "-f", path, ...smartArg]);
    }

    function preview(path: string): void {
        previewPath = path;
        showPreview = true;

        if (Colours.scheme === "dynamic")
            getPreviewColoursProc.running = true;
    }

    function stopPreview(): void {
        showPreview = false;
        if (!previewColourLock)
            Colours.showPreview = false;
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
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.actualCurrent = text().trim();
            root.previewColourLock = false;
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

    Process {
        id: getPreviewColoursProc

        command: ["caelestia", "wallpaper", "-p", root.previewPath, ...root.smartArg]
        stdout: StdioCollector {
            onStreamFinished: {
                Colours.load(text, true);
                Colours.showPreview = true;
            }
        }
    }
}
