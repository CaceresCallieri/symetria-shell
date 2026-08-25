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
    // Matches the STEP in hypr/scripts/brightnesscontrol.sh, so the keyboard
    // chord and the OSD wheel move brightness by the same amount. Brightness
    // takes a finer step than audio: 10% per notch overshoots comfortable levels.
    property real brightnessIncrement: 0.05
    // Floor for every brightness write, so no key repeat or drag to the bottom of
    // the dial leaves the panel at true black. Note 1% is still very dark on most
    // panels — this guarantees a non-zero backlight, NOT a readable screen. It is
    // deliberately low so a dark room can still be dimmed right down; raise it if
    // recovering from the bottom of the range matters more than that.
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
