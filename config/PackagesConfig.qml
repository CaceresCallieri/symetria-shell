import Quickshell.Io

JsonObject {
    property bool enabled: true
    property int debounceMs: 500
    property int maxResults: 50
    property int maxShown: 7
    property Sizes sizes: Sizes {}

    component Sizes: JsonObject {
        property int width: 600
        property int itemHeight: 69
    }
}
