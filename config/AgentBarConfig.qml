import Quickshell.Io

/// Agent bar configuration — controls the bottom bar strip that shows active Claude Code sessions.
JsonObject {
    property bool enabled: true
    /// When true and agents are present, workspace indicators merge into the bottom bar
    /// and the top bar's workspace pill hides (Mode 3). When false, both remain separate (Mode 2).
    property bool mergeWorkspaces: true
    property Sizes sizes: Sizes {}

    component Sizes: JsonObject {
        /// Height of the pill strip content area (excluding vertical padding).
        property int innerHeight: 24
    }
}
