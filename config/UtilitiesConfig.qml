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

        /// Height of the bottom-right hover strip that summons the utilities
        /// drawer, in pixels, measured up from the bottom screen edge.
        ///
        /// MUST be greater than zero. The strip is not merely a hit test:
        /// Wrapper.qml builds one input Region per Panels child and subtracts it
        /// from the click-through mask, so a zero-height trigger produces a
        /// zero-height region and the pointer is never delivered there at all.
        /// The drawer had no trigger zone of its own and relied on the mask's
        /// bottom strip, which is exactly `agentBar.implicitHeight` tall — so
        /// hiding the agent bar left the corner unhoverable and the drawer
        /// unopenable. Nothing errors when that happens; the compositor simply
        /// hands the event to the window underneath.
        ///
        /// The screen edge stops the pointer, so a few pixels are enough. Keep
        /// it narrow: these pixels stop belonging to the window underneath
        /// whenever the agent bar is not already covering them.
        property int triggerHeight: 6
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
