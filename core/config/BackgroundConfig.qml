import Quickshell.Io

JsonObject {
    property bool enabled: true
    property DesktopClock desktopClock: DesktopClock {}
    property Visualiser visualiser: Visualiser {}
    property PerWorkspaceWallpapers perWorkspaceWallpapers: PerWorkspaceWallpapers {}

    component DesktopClock: JsonObject {
        property bool enabled: false
    }

    component Visualiser: JsonObject {
        property bool enabled: false
        property bool autoHide: true
        property bool blur: false
        property real rounding: 1
        property real spacing: 1
    }

    component PerWorkspaceWallpapers: JsonObject {
        property bool enabled: true
        property string directory: "Workspaces"
        // Default "first" uses first workspace wallpaper for unmapped workspaces.
        // Changed from upstream "global" since path.txt state file was removed.
        property string fallbackBehavior: "first"

        // Fix 4: Validate fallbackBehavior enum values
        readonly property var validFallbacks: ["global", "first", "none"]

        onFallbackBehaviorChanged: {
            if (!validFallbacks.includes(fallbackBehavior)) {
                console.error(`Invalid fallbackBehavior: "${fallbackBehavior}". Valid options: ${validFallbacks.join(", ")}. Using "global".`);
                fallbackBehavior = "global";
            }
        }
    }
}
