import Quickshell.Io

JsonObject {
    property bool enabled: true
    property int maxToasts: 4

    property Sizes sizes: Sizes {}
    property Toasts toasts: Toasts {}
    property Vpn vpn: Vpn {}

    component Sizes: JsonObject {
        property int width: 430
        property int toastWidth: 430
    }

    component Toasts: JsonObject {
        property bool configLoaded: true
        property bool chargingChanged: true
        property bool gameModeChanged: true
        property bool dndChanged: true
        property bool audioOutputChanged: true
        property bool audioInputChanged: true
        property bool capsLockChanged: true
        property bool numLockChanged: true
        property bool kbLayoutChanged: true
        property bool vpnChanged: true
        property bool nowPlaying: false
        property bool focusModeChanged: true
        property bool clipboardCopied: true
        property bool windowUrgent: true
        // Window classes that should never produce an urgent toast.
        // Note: empty string ("") has no effect — windows with unresolved class are
        // dropped before the blocklist is checked (silent drop after the 250ms retry).
        property list<string> windowUrgentBlocklist: ["UnrealEditor"]
    }

    component Vpn: JsonObject {
        property bool enabled: false
        property list<var> provider: ["netbird"]
    }
}
