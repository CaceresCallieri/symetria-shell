pragma Singleton

import qs.config
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Update counts by source
    property int pacmanUpdates: 0
    property int aurUpdates: 0
    property int flatpakUpdates: 0
    property bool flatpakInstalled: false

    // Total count for display
    readonly property int totalUpdates: pacmanUpdates + aurUpdates + flatpakUpdates

    // Whether we have data loaded
    property bool hasData: false

    // Reference counting for lazy initialization
    property int refCount: 0

    // Track if update check is in progress (prevents process spam)
    property bool updateInProgress: false

    // Trigger a manual refresh (useful after system update)
    function refresh(): void {
        if (!updateInProgress) {
            updateProcess.running = true;
        }
    }

    Timer {
        running: root.refCount > 0
        interval: 90000  // 90 seconds, same as AGS implementation
        repeat: true
        triggeredOnStart: true
        onTriggered: updateProcess.running = true
    }

    // Listen for custom Hyprland event to refresh after system update
    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            // Custom events dispatched via: hyprctl dispatch custom system-updated
            if (event.name === "custom" && event.data === "system-updated") {
                root.refresh();
            }
        }
    }

    Process {
        id: updateProcess

        onRunningChanged: root.updateInProgress = running

        command: ["sh", "-c", String.raw`
            pacman_updates=$(checkupdates 2>/dev/null | wc -l)
            aur_updates=$(paru -Qua 2>/dev/null | wc -l)

            if command -v flatpak >/dev/null 2>&1; then
                flatpak_installed=true
                flatpak_updates=$(flatpak remote-ls --updates 2>/dev/null | wc -l)
            else
                flatpak_installed=false
                flatpak_updates=0
            fi

            printf '{"pacman":%d,"aur":%d,"flatpak":%d,"flatpakInstalled":%s}\n' "$pacman_updates" "$aur_updates" "$flatpak_updates" "$flatpak_installed"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text || text.trim() === "") {
                    console.warn("Updates: Empty output from update check");
                    return;
                }
                try {
                    const data = JSON.parse(text.trim());
                    root.pacmanUpdates = data.pacman;
                    root.aurUpdates = data.aur;
                    root.flatpakUpdates = data.flatpak;
                    root.flatpakInstalled = data.flatpakInstalled;
                    root.hasData = true;
                } catch (e) {
                    console.error("Updates: Failed to parse update data:", e, text);
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") {
                    console.warn("Updates: stderr:", text.trim());
                }
            }
        }
    }
}
