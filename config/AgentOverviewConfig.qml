import Quickshell.Io

/// Agent overview configuration — the Super+A fullscreen overlay that lists every
/// live agent (IDE, standalone nvim, remote), grouped by workspace, with an
/// active/dormant filter.
JsonObject {
    property bool enabled: true
    property Sizes sizes: Sizes {}

    component Sizes: JsonObject {
        /// Fixed width of each agent card; the grid wraps cards to fit the screen.
        /// Wide enough for a readable recent-conversation preview.
        property int cardWidth: 380
    }
}
