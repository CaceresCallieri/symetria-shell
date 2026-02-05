import Quickshell.Io

JsonObject {
    property bool enabled: true
    property int maxHistory: 50         // Maximum calculation history entries
    property bool copyOnEnter: false    // Auto-copy result to clipboard on Enter
    property Sizes sizes: Sizes {}

    component Sizes: JsonObject {
        property int width: 675              // 1.5x base width (450) for longer expressions
        property int historyItemHeight: 40
        property int maxVisibleHistory: 8
    }
}
