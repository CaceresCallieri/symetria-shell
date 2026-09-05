import Quickshell.Io

JsonObject {
    property bool enabled: true
    property DesktopClock desktopClock: DesktopClock {}
    property Visualiser visualiser: Visualiser {}
    property PerWorkspaceWallpapers perWorkspaceWallpapers: PerWorkspaceWallpapers {}
    property FocusBackdrop focusBackdrop: FocusBackdrop {}

    component FocusBackdrop: JsonObject {
        // When true, the frozen metal sheet (modules/background/MetalWallpaper.qml)
        // is shown INSTEAD OF the bare surface while focus mode is active.
        // Normal (non-focus) wallpapers are untouched.
        property bool enabled: false
        // Frozen moment of the travelling wave — the composition seed of the
        // still frame. Change to re-composite; takes effect live. Clamped to
        // [0, 86400] at the uniform (out-of-range values would lose float32
        // precision in the shader's noise lookup).
        property real time: 40
    }

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
