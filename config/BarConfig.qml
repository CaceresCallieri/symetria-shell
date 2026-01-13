import Quickshell.Io
import qs.config

JsonObject {
    property bool persistent: true
    property bool showOnHover: true
    property int dragThreshold: 20
    property ScrollActions scrollActions: ScrollActions {}
    property Popouts popouts: Popouts {}
    property Workspaces workspaces: Workspaces {}
    property Tray tray: Tray {}
    property Status status: Status {}
    property Clock clock: Clock {}
    property Sizes sizes: Sizes {}
    property list<string> excludedScreens: []

    property list<var> entries: [
        {
            id: "clock",
            enabled: true
        },
        {
            id: "date",
            enabled: true
        },
        {
            id: "cpuStatus",
            enabled: true
        },
        {
            id: "ramUsage",
            enabled: true
        },
        {
            id: "availableUpdates",
            enabled: true
        },
        {
            id: "spacer",
            enabled: true
        },
        {
            id: "workspaces",
            enabled: true
        },
        {
            id: "spacer",
            enabled: true
        },
        {
            id: "tray",
            enabled: true
        },
        {
            id: "statusIcons",
            enabled: true
        },
        {
            id: "power",
            enabled: true
        }
    ]
    component ScrollActions: JsonObject {
        property bool workspaces: true
        property bool volume: true
        property bool brightness: true
    }

    component Popouts: JsonObject {
        property bool tray: true
        property bool statusIcons: true
    }

    component Workspaces: JsonObject {
        property int shown: 5
        property bool showOnlyOccupied: false
        property bool activeIndicator: true
        property bool occupiedBg: false
        property bool showWindows: true
        property bool showWindowsOnSpecialWorkspaces: showWindows
        property bool activeTrail: false
        property bool perMonitorWorkspaces: true
        // App icon features (ported from AGS bar)
        property bool useActualAppIcons: true      // Use .desktop file icons instead of Material category icons
        property bool terminalAppDetection: true   // Detect apps running in terminals (nvim, yazi, etc.)
        property bool appIconsClickToFocus: true   // Click on icon to focus that window
        property list<var> specialWorkspaceIcons: [
            { name: "special", icon: "mat:lightbulb" },
            { name: "communications", icon: "mat:phone" },
            { name: "note-taking", icon: "mat:auto_stories" }
        ]
        property list<var> namedWorkspaceIcons: [
            { name: "gaming", icon: "mat:sports_esports" },
            { name: "music", icon: "mat:library_music" },
            { name: "theater", icon: "mat:theater_comedy" }
        ]
    }
    component Tray: JsonObject {
        property bool background: false
        property bool recolour: false
        property bool compact: false
        property list<var> iconSubs: []
    }

    component Status: JsonObject {
        property bool showAudio: false
        property bool showMicrophone: false
        property bool showKbLayout: false
        property bool showNetwork: true
        property bool showBluetooth: true
        property bool showBattery: true
        property bool showLockStatus: true
    }

    component Clock: JsonObject {
        property bool showIcon: true
    }

    component Sizes: JsonObject {
        property int innerWidth: 40
        readonly property int indicatorHeight: innerWidth - Appearance.padding.small * 2
        property int iconSize: 18  // Shared by workspace app icons and tray icons
        property int trayMenuWidth: 300
        property int batteryWidth: 250
        property int networkWidth: 320
    }
}
