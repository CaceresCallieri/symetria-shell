import Quickshell.Io

JsonObject {
    property bool enabled: true
    property bool showOnHover: false
    property int maxShown: 10
    property int previewLength: 80
    property int dragThreshold: 50
    property Sizes sizes: Sizes {}

    component Sizes: JsonObject {
        property int itemWidth: 500
        property int itemHeight: 48
    }
}
