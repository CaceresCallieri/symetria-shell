import Quickshell.Io

JsonObject {
    property bool enabled: true
    property Sizes sizes: Sizes {}

    component Sizes: JsonObject {
        property int itemWidth: 160
        property int keyWidth: 32
        property int itemHeight: 28
    }
}
