import Quickshell.Io

JsonObject {
    property bool expire: true
    property int defaultExpireTimeout: 5000
    property real clearThreshold: 0.3
    property int expandThreshold: 20
    property bool actionOnClick: false
    property int groupPreviewNum: 3
    property bool openExpanded: false // Show the notification in expanded state when opening
    property int maxStored: 1000 // Maximum notifications to keep in memory and on disk
    property Sizes sizes: Sizes {}

    component Sizes: JsonObject {
        property int width: 400
        // Image is the icon-area RESERVATION (a square layout box at the
        // card's left). The colored disc inside is 75% of this. The previous
        // default (41) was tuned for the upstream caelestia padding scale
        // (1.0). Symmetria's compact default appearance (padding scale 0.6)
        // made the disc dominate the card vertically. 32 lands a 24px disc
        // that reads as an icon without overwhelming the surrounding text.
        property int image: 32
        // Badge size only applies when the notification also has a main
        // image (the disc collapses to a bottom-right corner overlay).
        // Scaled proportionally to the new image size.
        property int badge: 16
    }
}
