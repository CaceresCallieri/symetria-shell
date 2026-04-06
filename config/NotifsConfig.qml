import Quickshell.Io

JsonObject {
    property bool expire: true
    property int defaultExpireTimeout: 5000
    property real clearThreshold: 0.3
    property int expandThreshold: 20
    property bool actionOnClick: false
    property int groupPreviewNum: 3
    property bool openExpanded: false // Show the notifichation in expanded state when opening
    property int maxStored: 1000 // Maximum notifications to keep in memory and on disk
    property Sizes sizes: Sizes {}

    component Sizes: JsonObject {
        property int width: 400
        property int image: 41
        property int badge: 20
    }
}
