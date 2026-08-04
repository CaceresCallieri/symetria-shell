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
    property Date date: Date {}
    property TimePill timePill: TimePill {}
    property SystemPill systemPill: SystemPill {}
    property Sizes sizes: Sizes {}
    property list<string> excludedScreens: []

    property list<var> entries: [
        {
            id: "timePill",
            enabled: true
        },
        {
            id: "systemPill",
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
        property bool timePill: true
        property bool systemPill: true
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
            { name: "theater", icon: "mat:theater_comedy" },
            { name: "symmetria", icon: "mat:balance" },
            { name: "symmetria-whatsapp", icon: "mat:chat" },
            { name: "netcolor", icon: "mat:palette" },
            { name: "bambin", icon: "mat:format_paint" },
            { name: "fps-game", icon: "mat:target" },
            { name: ".dotfiles", icon: "mat:settings" },
            { name: ".hyprdots", icon: "mat:tune" },
            { name: "kosmos", icon: "mat:rocket_launch" },
            { name: "nvim", icon: "mat:edit" }
        ]
    }
    component Tray: JsonObject {
        property bool background: false
        // Matches the shipped shell.json. Kept in sync deliberately: a QML
        // default that disagrees with the shipped override means anyone who
        // deletes or regenerates shell.json silently gets different behaviour —
        // here, raw app pixmaps blowing past the palette's brightness ceiling.
        // Rationale for flattening tray icons is on TrayItem.qml's layer.enabled.
        property bool recolour: true
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
        property bool showPowerProfile: true
        property bool showLockStatus: true
        // Show a "dictation active" icon while STT streaming mode is toggled on
        // (SttService.streamingActive). The icon only appears when streaming is
        // active; this flag lets it be disabled entirely.
        property bool showDictationStatus: true
    }

    component Clock: JsonObject {
        property bool showIcon: true  // Display clock icon (schedule)
    }

    component Date: JsonObject {
        property bool showIcon: true  // Display calendar icon (calendar_month)
    }

    component TimePill: JsonObject {
        property bool showClock: true
        property bool showDate: true
        property bool showWeather: true
    }

    component SystemPill: JsonObject {
        property bool showCpu: true
        property bool showRam: true
        property bool showUpdates: true
    }

    component Sizes: JsonObject {
        property int innerWidth: 40
        readonly property int indicatorHeight: innerWidth - Appearance.padding.small * 2
        property int iconSize: 18  // Shared by workspace app icons and tray icons
        property int edgePadding: Appearance.padding.large  // Left/right margin at bar edges
        property int trayMenuWidth: 300
        property int batteryWidth: 250
        property int networkWidth: 320
        property int weatherWidth: 250
        property int updatesWidth: 200
        // Much wider while a run is in progress: the progress view shows a phase
        // line, current package name, and a tall live log that need real estate —
        // sized so full pacman/makepkg lines are readable without elision.
        property int updatesProgressWidth: 680
        // Compact width for the password-entry step: just a label, a short
        // password field, and the Update button.
        property int updatesPasswordWidth: 340
        // Wider than updatesWidth: the RAM popout's process list shows
        // long executable names (e.g. claude-code, zen-browser) and a
        // %-column on the right, which together over-elide the name
        // column at 200px. 290px gives the name column ~90px more room
        // without making the popout dominate the bar.
        property int ramWidth: 290
        property int calendarWidth: 300
    }
}
