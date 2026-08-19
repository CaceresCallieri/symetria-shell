import Quickshell.Io
import QtQuick

JsonObject {
    property string weatherLocation: "" // A lat,long pair or empty for autodetection, e.g. "37.8267,-122.4233"
    property bool weatherUseCurrentLocation: false // GPS via geoclue; falls back to IP geolocation if unavailable
    property bool useFahrenheit: [Locale.ImperialUSSystem, Locale.ImperialSystem].includes(Qt.locale().measurementSystem)
    property bool useTwelveHourClock: Qt.locale().timeFormat(Locale.ShortFormat).toLowerCase().includes("a")
    property string gpuType: ""
    property int visualiserBars: 45
    property real audioIncrement: 0.1
    property real brightnessIncrement: 0.1
    // Floor for every brightness write, so no key repeat or drag to the bottom of
    // the dial can black out a panel the user then cannot see to recover. Set to 0
    // only if every display here has a physical control to bring it back.
    property real minBrightness: 0.01
    property real maxVolume: 1.0
    property string defaultPlayer: "Spotify"
    property list<var> playerAliases: [
        {
            "from": "com.github.th_ch.youtube_music",
            "to": "YT Music"
        }
    ]
}
