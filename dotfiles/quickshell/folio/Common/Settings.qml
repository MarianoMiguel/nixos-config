pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Folio's own preferences (~/.config/folio/settings.json; the harness keeps
// its own under $XDG_RUNTIME_DIR): everything that is
// not the palette selection. get("dock.icons") returns the saved value or the
// default below; set() saves at once. Edits to the file apply live.
Singleton {
    id: root

    readonly property var defaults: ({
        "motion": "full",                       // full | gentle | still
        "dock.icons": "original",               // original | plated | printed
        "dock.magnify": true,
        "dock.reserve": true,                   // windows stop above the dock
        "dock.pinned": ["org.gnome.Nautilus", "google-chrome", "com.mitchellh.ghostty", "spotify", "code"],
        "sidebar.side": "right",
        "world.cities": [["Campana", "America/Argentina/Buenos_Aires"], ["New York", "America/New_York"], ["Los Angeles", "America/Los_Angeles"], ["Sydney", "Australia/Sydney"]],
        "weather.place": ["Campana", -34.16, -58.96],
        "screensaver.after": 300,               // seconds idle; 0 never
        "idle.lockBattery": 300,
        "idle.lockAC": 600,
        "idle.screensOff": 30,                  // seconds after locking
        "idle.hibernateBattery": 900,
        "plates.breathe": 1,
        "plates.dark": "moonlit",               // moonlit | negative
        "island.live": true,
        "login.score": true,
        "sounds": false,
        "night.schedule": "off",                // off | sunset | custom | always
        "night.from": "22:00",
        "night.to": "07:00",
        "night.warmth": 0.5,                    // 0 (6000 K) to 1 (2700 K)
        "displays.clamshell": true,             // lid closed + another display: built-in off
        "text.scale": 1,                        // Folio's text (and GTK apps' text-scaling-factor)
        "contrast": "normal",                   // normal | high
        "colors.invert": false,
        "sound.overamplify": false,             // volume up to 150%
        "drives.automount": true                // mount removable drives when plugged in
    })
    property var data: ({})
    // The harness keeps its own copy, so tests never change the real preferences.
    readonly property string dir: Quickshell.env("FOLIO_HARNESS") ? (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/folio-settings" : Quickshell.env("HOME") + "/.config/folio"
    readonly property string path: dir + "/settings.json"

    function get(key) { return key in data ? data[key] : defaults[key]; }
    function set(key, value) {
        const d = Object.assign({}, data);
        d[key] = value;
        data = d;
        file.setText(JSON.stringify(d, null, 2) + "\n");
    }

    Process { running: true; command: ["mkdir", "-p", root.dir] }
    FileView {
        id: file
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.data = JSON.parse(text()); } catch (e) { console.warn("Settings: unreadable", e); } }
    }

    // Motion level for everything: 1, 0.5, or near zero ("still").
    readonly property real motion: get("motion") === "still" ? 0.01 : get("motion") === "gentle" ? 0.5 : 1
}
