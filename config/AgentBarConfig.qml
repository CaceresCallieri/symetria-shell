import Quickshell.Io

/// Agent bar configuration — controls the bottom bar strip that shows active Claude Code sessions.
JsonObject {
    property bool enabled: true
    /// When true and agents are present, workspace indicators merge into the bottom bar
    /// and the top bar's workspace pill hides (Mode 3). When false, both remain separate (Mode 2).
    // Off since Mesura Code became a second source. Its threads have no
    // Hyprland window and therefore no workspace, so the merged layout — which
    // is organised BY workspace — has nowhere to put them. The separate layout
    // asks for none: a project pill needs a name and a list of agents.
    //
    // The cost is accepted and not free: the IDE's own agents lose their
    // workspace association in the top bar too, for as long as the IDE is
    // still in use.
    property bool mergeWorkspaces: false
    property Sizes sizes: Sizes {}

    component Sizes: JsonObject {
        /// Height of the pill strip content area (excluding vertical padding).
        property int innerHeight: 24
    }
}
