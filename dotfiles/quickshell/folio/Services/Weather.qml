pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// The weather at Settings "weather.place" ([name, lat, lon]) from open-meteo,
// every 30 minutes. Offline keeps the last reading (cached across restarts);
// with none, summary is just the place.
Singleton {
    id: root

    readonly property var place: Settings.get("weather.place") || []
    readonly property string placeKey: JSON.stringify(place)
    readonly property string name: place[0] || ""
    property real temperature: NaN
    property int code: -1
    property bool isDay: true
    property real updated: 0
    readonly property bool available: code >= 0 && !isNaN(temperature)
    readonly property string condition: describe(code)
    // "Campana · 19° · clear"
    readonly property string summary: [name].concat(available ? [Math.round(temperature) + "°", condition] : []).filter(s => s).join(" · ")

    // WMO weather codes, in words.
    function describe(c) {
        if (c < 0) return "";
        if (c === 0) return "clear";
        if (c === 1) return "mostly clear";
        if (c === 2) return "partly cloudy";
        if (c === 3) return "overcast";
        if (c === 45 || c === 48) return "fog";
        if (c >= 51 && c <= 55) return "drizzle";
        if (c === 56 || c === 57 || c === 66 || c === 67) return "freezing rain";
        if (c >= 61 && c <= 65) return "rain";
        if (c >= 71 && c <= 77) return "snow";
        if (c >= 80 && c <= 82) return "showers";
        if (c === 85 || c === 86) return "snow showers";
        if (c >= 95) return "storm";
        return "";
    }

    function refresh() {
        if (place.length < 3 || fetch.running) return;
        fetch.running = true;
    }

    Process {
        id: fetch
        command: ["curl", "-sf", "--max-time", "15",
            "https://api.open-meteo.com/v1/forecast?latitude=" + root.place[1] + "&longitude=" + root.place[2]
            + "&current=temperature_2m,weather_code,is_day&timezone=auto"]
        stdout: StdioCollector {
            onStreamFinished: {
                let c;
                try { c = JSON.parse(text).current; } catch (e) { return; }
                if (!c || c.temperature_2m === undefined) return;
                root.temperature = c.temperature_2m;
                root.code = c.weather_code;
                root.isDay = c.is_day === 1;
                root.updated = Date.now();
                cache.setText(JSON.stringify({ "place": root.place, "temperature": root.temperature, "code": root.code, "isDay": root.isDay, "updated": root.updated }));
            }
        }
    }

    // The last reading, if it is for this place and under six hours old.
    FileView {
        id: cache
        path: Quickshell.statePath("weather.json")
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                if (JSON.stringify(s.place) !== root.placeKey || Date.now() - s.updated > 6 * 3600000) return;
                root.temperature = s.temperature; root.code = s.code; root.isDay = s.isDay; root.updated = s.updated;
            } catch (e) {}
        }
    }

    Timer { interval: 30 * 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
    // Back online after a miss: try again at once.
    Connections {
        target: Network
        function onOnlineChanged() { if (Network.online && Date.now() - root.updated > 30 * 60000) root.refresh(); }
    }
    onPlaceKeyChanged: { temperature = NaN; code = -1; refresh(); }
}
