pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import "../Common/Sun.js" as Sun

// Night light: warmer colors in the evening, through wl-gammarelay-rs (niri's
// gamma control). Off, from sunset to sunrise at Settings' weather place, on
// custom hours, or always. Turning on or off fades over a few seconds.
// "Until tomorrow" (snooze) pauses it until the schedule next changes.
// The same relay inverts the screen's colors (Settings › Accessibility).
// In the harness nothing reaches the screen.
Singleton {
    id: root

    readonly property string schedule: Settings.get("night.schedule") || "off"
    readonly property real warmth: Settings.get("night.warmth")
    readonly property int nightTemp: Math.round(6000 - Math.max(0, Math.min(1, warmth)) * 3300)
    readonly property var place: Settings.get("weather.place") || ["Campana", -34.16, -58.96]

    property date now: new Date()
    Timer { interval: 30000; repeat: true; running: root.schedule !== "off"; triggeredOnStart: true; onTriggered: root.now = new Date() }

    function minutes(hhmm) { const r = /^(\d{1,2}):(\d{2})$/.exec(hhmm || ""); return r ? (+r[1]) * 60 + (+r[2]) : -1; }
    readonly property bool due: {
        if (schedule === "always") return true;
        if (schedule === "sunset") return Sun.isNight(now, place[1], place[2]);
        if (schedule === "custom") {
            const m = now.getHours() * 60 + now.getMinutes(), a = minutes(Settings.get("night.from")), b = minutes(Settings.get("night.to"));
            if (a < 0 || b < 0 || a === b) return false;
            return a < b ? (m >= a && m < b) : (m >= a || m < b);
        }
        return false;
    }
    property bool snoozed: false
    onDueChanged: snoozed = false
    readonly property bool active: due && !snoozed
    // Sunset's times, for the page: "From 19:20 to 05:58".
    readonly property var sun: Sun.times(now, place[1], place[2])

    property real temp: active ? nightTemp : 6500
    Behavior on temp { NumberAnimation { duration: 2500; easing.type: Easing.InOutSine } }

    readonly property bool harness: !!Quickshell.env("FOLIO_HARNESS")
    readonly property bool invert: Settings.get("colors.invert") === true
    Process {
        id: relay
        running: !root.harness && (root.schedule !== "off" || root.temp < 6490 || root.invert)
        command: ["wl-gammarelay-rs", "run"]
    }
    property int pushed: 6500
    Timer {
        interval: 200; repeat: true
        running: relay.running && Math.round(root.temp) !== root.pushed
        onTriggered: {
            root.pushed = Math.round(root.temp);
            Quickshell.execDetached(["busctl", "--user", "set-property", "rs.wl-gammarelay", "/", "rs.wl.gammarelay", "Temperature", "q", String(root.pushed)]);
        }
    }
    function pushInvert() {
        Quickshell.execDetached(["busctl", "--user", "set-property", "rs.wl-gammarelay", "/", "rs.wl.gammarelay", "Inverted", "b", String(root.invert)]);
    }
    onInvertChanged: if (relay.running) pushInvert()
    // The relay starts neutral: push the current state once it is up.
    Timer { interval: 600; running: relay.running; onTriggered: { root.pushed = 0; if (root.invert) root.pushInvert(); } }
}
