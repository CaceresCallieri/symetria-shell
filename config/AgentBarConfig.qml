import Quickshell.Io

/// Agent bar configuration — controls the bottom bar strip that shows active Claude Code sessions.
JsonObject {
    property bool enabled: true
    property Sizes sizes: Sizes {}

    component Sizes: JsonObject {
        /// Height of the pill strip content area (excluding vertical padding).
        property int innerHeight: 24
    }
}
