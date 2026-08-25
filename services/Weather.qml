pragma Singleton

import qs.config
import qs.utils
import Symmetria
import Quickshell
import Quickshell.Io
import QtQuick
import QtPositioning

Singleton {
    id: root

    property string city
    property string loc
    // Initialize to null (not the implicit `undefined`) so consumers' `cc !== null`
    // guards work: `undefined !== null` is true, which would falsely treat "no data yet"
    // as "data available" and render a bait 0° before any fetch succeeds.
    property var cc: null
    property list<var> forecast
    property list<var> hourlyForecast

    // Whether the geoclue daemon is installed (detected via its D-Bus service file).
    // Surfaced in the control-center Services pane to prompt installation when GPS
    // mode is enabled but unavailable. `geoclueChecked` gates UI on the async probe
    // so the "not installed" hint doesn't flash before the check completes.
    property bool geoclueAvailable: false
    property bool geoclueChecked: false
    // Gates the Connections block against JsonAdapter deserialization at startup.
    // Without this, Config.services property changes during initial JSON load trigger
    // a second reload() while an in-flight IP request from Component.onCompleted is
    // still pending — the late IP response can then overwrite the correct location.
    property bool ready: false
    // Prevents concurrent ipinfo.io requests when the GPS timeout and sourceError
    // both fire (geoclue plugin may emit sourceError on forced deactivation).
    property bool ipFetchInFlight: false

    readonly property string icon: cc ? Icons.getWeatherIcon(cc.weatherCode) : "cloud_alert"
    readonly property string description: cc?.weatherDesc ?? qsTr("No weather")
    readonly property string temp: Config.services.useFahrenheit ? `${cc?.tempF ?? 0}°F` : `${cc?.tempC ?? 0}°C`
    readonly property string feelsLike: Config.services.useFahrenheit ? `${cc?.feelsLikeF ?? 0}°F` : `${cc?.feelsLikeC ?? 0}°C`
    readonly property int humidity: cc?.humidity ?? 0
    readonly property real windSpeed: cc?.windSpeed ?? 0
    readonly property string sunrise: cc ? Qt.formatDateTime(new Date(cc.sunrise), Config.services.useTwelveHourClock ? "h:mm A" : "h:mm") : "--:--"
    readonly property string sunset: cc ? Qt.formatDateTime(new Date(cc.sunset), Config.services.useTwelveHourClock ? "h:mm A" : "h:mm") : "--:--"
    readonly property string tempMax: forecast.length > 0 ? (Config.services.useFahrenheit ? `${forecast[0].maxTempF}°` : `${forecast[0].maxTempC}°`) : ""
    readonly property string tempMin: forecast.length > 0 ? (Config.services.useFahrenheit ? `${forecast[0].minTempF}°` : `${forecast[0].minTempC}°`) : ""

    readonly property var cachedCities: new Map()

    function reload(): void {
        // Explicit "current location" mode: resolve via geoclue GPS, falling back to IP.
        if (Config.services.weatherUseCurrentLocation) {
            requestGpsLocation();
            return;
        }

        const configLocation = Config.services.weatherLocation;

        if (configLocation) {
            if (configLocation.indexOf(",") !== -1 && !isNaN(parseFloat(configLocation.split(",")[0]))) {
                loc = configLocation;
                fetchCityFromCoords(configLocation);
            } else {
                fetchCoordsFromCity(configLocation);
            }
        } else {
            // No manual location configured: auto-detect via IP geolocation.
            fetchLocationFromIp();
        }
    }

    // IP-based geolocation via ipinfo.io. Shared fallback used both when no manual
    // location is configured and when a geoclue GPS fix is unavailable. Cached for
    // 15 min (tracked by `timer`) so repeated reloads don't hammer the endpoint.
    function fetchLocationFromIp(): void {
        if (root.ipFetchInFlight)
            return; // deduplicate concurrent calls (GPS timeout + sourceError race)
        if (loc && timer.elapsed() <= 900000)
            return;

        root.ipFetchInFlight = true;
        Requests.get("https://ipinfo.io/json", text => {
            root.ipFetchInFlight = false;
            const response = JSON.parse(text);
            if (response.loc) {
                loc = response.loc;
                city = response.city ?? "";
                timer.restart();
            }
        });
    }

    // One-shot geoclue request. Activates the PositionSource; resolution happens in
    // gpsSource.onPositionChanged (success), onSourceErrorChanged (failure), or
    // gpsTimeout (no response) — each converging on a valid `loc` or the IP fallback.
    function requestGpsLocation(): void {
        if (loc && timer.elapsed() <= 900000)
            return; // reuse a still-fresh fix instead of re-querying geoclue

        gpsTimeout.restart();
        gpsSource.active = true;
    }

    function fetchCityFromCoords(coords: string): void {
        if (cachedCities.has(coords)) {
            city = cachedCities.get(coords);
            return;
        }

        const [lat, lon] = coords.split(",");
        const url = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lon}&format=geocodejson`;
        Requests.get(url, text => {
            const geo = JSON.parse(text).features?.[0]?.properties.geocoding;
            if (geo) {
                const geoCity = geo.type === "city" ? geo.name : geo.city;
                city = geoCity;
                cachedCities.set(coords, geoCity);
            } else {
                city = "Unknown City";
            }
        });
    }

    function fetchCoordsFromCity(cityName: string): void {
        const url = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(cityName)}&count=1&language=en&format=json`;

        Requests.get(url, text => {
            const json = JSON.parse(text);
            if (json.results && json.results.length > 0) {
                const result = json.results[0];
                loc = result.latitude + "," + result.longitude;
                city = result.name;
            } else {
                loc = "";
                reload();
            }
        });
    }

    function fetchWeatherData(): void {
        const url = getWeatherUrl();
        if (url === "")
            return;

        Requests.get(url, text => {
            const json = JSON.parse(text);
            if (!json.current || !json.daily)
                return;

            cc = {
                weatherCode: json.current.weather_code,
                weatherDesc: getWeatherCondition(json.current.weather_code),
                tempC: Math.round(json.current.temperature_2m),
                tempF: Math.round(toFahrenheit(json.current.temperature_2m)),
                feelsLikeC: Math.round(json.current.apparent_temperature),
                feelsLikeF: Math.round(toFahrenheit(json.current.apparent_temperature)),
                humidity: json.current.relative_humidity_2m,
                windSpeed: json.current.wind_speed_10m,
                isDay: json.current.is_day,
                sunrise: json.daily.sunrise[0],
                sunset: json.daily.sunset[0]
            };

            const forecastList = [];
            for (let i = 0; i < json.daily.time.length; i++)
                forecastList.push({
                    date: json.daily.time[i],
                    maxTempC: Math.round(json.daily.temperature_2m_max[i]),
                    maxTempF: Math.round(toFahrenheit(json.daily.temperature_2m_max[i])),
                    minTempC: Math.round(json.daily.temperature_2m_min[i]),
                    minTempF: Math.round(toFahrenheit(json.daily.temperature_2m_min[i])),
                    weatherCode: json.daily.weather_code[i],
                    icon: Icons.getWeatherIcon(json.daily.weather_code[i])
                });
            forecast = forecastList;

            const hourlyList = [];
            const now = new Date();
            for (let i = 0; i < json.hourly.time.length; i++) {
                const time = new Date(json.hourly.time[i]);
                if (time < now)
                    continue;

                hourlyList.push({
                    timestamp: json.hourly.time[i],
                    hour: time.getHours(),
                    tempC: Math.round(json.hourly.temperature_2m[i]),
                    tempF: Math.round(toFahrenheit(json.hourly.temperature_2m[i])),
                    weatherCode: json.hourly.weather_code[i],
                    icon: Icons.getWeatherIcon(json.hourly.weather_code[i])
                });
            }
            hourlyForecast = hourlyList;
        });
    }

    function toFahrenheit(celcius: real): real {
        return celcius * 9 / 5 + 32;
    }

    function getWeatherUrl(): string {
        if (!loc || loc.indexOf(",") === -1)
            return "";

        const [lat, lon] = loc.split(",");
        const baseUrl = "https://api.open-meteo.com/v1/forecast";
        const params = ["latitude=" + lat, "longitude=" + lon, "hourly=weather_code,temperature_2m", "daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset", "current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m", "timezone=auto", "forecast_days=7"];

        return baseUrl + "?" + params.join("&");
    }

    function getWeatherCondition(code: string): string {
        const conditions = {
            "0": "Clear",
            "1": "Clear",
            "2": "Partly cloudy",
            "3": "Overcast",
            "45": "Fog",
            "48": "Fog",
            "51": "Drizzle",
            "53": "Drizzle",
            "55": "Drizzle",
            "56": "Freezing drizzle",
            "57": "Freezing drizzle",
            "61": "Light rain",
            "63": "Rain",
            "65": "Heavy rain",
            "66": "Light rain",
            "67": "Heavy rain",
            "71": "Light snow",
            "73": "Snow",
            "75": "Heavy snow",
            "77": "Snow",
            "80": "Light rain",
            "81": "Rain",
            "82": "Heavy rain",
            "85": "Light snow showers",
            "86": "Heavy snow showers",
            "95": "Thunderstorm",
            "96": "Thunderstorm with hail",
            "99": "Thunderstorm with hail"
        };
        return conditions[code] || "Unknown";
    }

    Component.onCompleted: {
        reload();
        ready = true; // allow Connections to react to live config changes from here on
    }
    onLocChanged: fetchWeatherData()

    // Refresh weather data hourly; also re-check location in case it has changed
    Timer {
        interval: 3600000 // 1 hour
        running: true
        repeat: true
        onTriggered: {
            reload();         // re-fetch location if missing or stale (offline recovery)
            fetchWeatherData(); // always refresh weather data when loc is already known
        }
    }

    ElapsedTimer {
        id: timer
    }

    // Probe for the geoclue daemon once at startup. The D-Bus system-service file is
    // present iff the `geoclue` package is installed; exit 0 → available.
    Process {
        id: geoclueProbe

        running: true
        command: ["test", "-e", "/usr/share/dbus-1/system-services/org.freedesktop.GeoClue2.service"]
        onExited: (code, status) => {
            root.geoclueAvailable = code === 0;
            root.geoclueChecked = true;
        }
    }

    // GPS via geoclue. Activated on demand by requestGpsLocation(); resolves to a
    // single fix then deactivates (one-shot). Requires the `geoclue` daemon installed
    // and Symmetria's desktopId whitelisted in /etc/geoclue/geoclue.conf — otherwise
    // sourceError fires (or the request times out) and we fall back to IP geolocation.
    PositionSource {
        id: gpsSource

        name: "geoclue2"

        PluginParameter {
            name: "desktopId"
            value: "symmetria"
        }

        onPositionChanged: {
            const coord = position.coordinate;
            if (coord.isValid) {
                gpsTimeout.stop();
                active = false; // one-shot: a single fix is enough
                loc = `${coord.latitude},${coord.longitude}`;
                fetchCityFromCoords(loc); // reuse reverse-geocode + cache
                timer.restart();
            }
        }

        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError) {
                active = false;
                gpsTimeout.stop();
                root.fetchLocationFromIp(); // geoclue unavailable/denied → graceful fallback
            }
        }
    }

    Timer {
        id: gpsTimeout

        interval: 10000 // no geoclue response within 10s → fall back to IP
        onTriggered: {
            gpsSource.active = false;
            if (!root.loc)
                root.fetchLocationFromIp();
        }
    }

    // React to live config edits (e.g. the control-center Services pane) so weather
    // refreshes immediately instead of waiting for the hourly timer.
    Connections {
        target: Config.services

        function onWeatherUseCurrentLocationChanged(): void {
            if (!root.ready)
                return;
            root.loc = "";
            root.city = "";
            root.reload();
        }

        function onWeatherLocationChanged(): void {
            if (!root.ready)
                return;
            root.loc = "";
            root.city = "";
            root.reload();
        }
    }
}
