import Quickshell.Io

JsonObject {
    property bool enabled: true
    property int historyLength: 5       // Maximum number of keys in history
    property int fadeoutDelay: 2000     // ms before older keys start fading
    property int fadeoutDuration: 500   // ms for fade animation
    property bool showMouseClicks: true // Show mouse button clicks as graphical icons
}
