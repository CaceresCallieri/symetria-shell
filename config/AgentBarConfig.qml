import Quickshell.Io

/// Agent bar configuration — controls the bottom bar strip that shows Mesura
/// Code's projects and their threads.
///
/// `mergeWorkspaces` used to select a second layout that folded the Hyprland
/// workspace indicators into this bar and hid the top bar's workspace pill. It
/// was switched off when Mesura Code became the bar's source — a Mesura thread
/// has no window and therefore no workspace, and that layout was organised by
/// workspace — and it was removed outright with Symmetria IDE. A shell.json
/// that still carries the key is harmless: an unknown key is ignored.
JsonObject {
    property bool enabled: true
    property Sizes sizes: Sizes {}

    component Sizes: JsonObject {
        /// Height of the pill strip content area (excluding vertical padding).
        property int innerHeight: 24
    }
}
