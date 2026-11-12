pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The panel's backlight. brightnessctl finds it (once, at start) and sets it
// (it holds the privileges); the level is read straight from sysfs, which
// starts nothing: when the sidebar opens and every 15 s while it stays open
// (unlocked), and before each step, so the keys start from the real level.
// A level Folio set in the last two seconds wins over a read, which could
// still see the value before brightnessctl wrote the new one. changed()
// feeds the island.
Singleton {
    id: root

    property real level: 0.5
    property bool available: false
    property string device: ""              // the backlight brightnessctl picked (amdgpu_bl1)
    property real max: 0
    property real setAt: 0
    signal changed()

    function refresh() {
        if (device === "") { reader.running = true; return; }
        if (Date.now() - setAt < 2000) return;
        current.reload();
        const t = current.text().trim();
        if (t !== "" && max > 0) level = Number(t) / max;
    }
    function set(v) {
        level = Math.max(0.01, Math.min(1, v));
        setAt = Date.now();
        Quickshell.execDetached(["brightnessctl", "-q", "set", Math.round(level * 100) + "%"]);
        changed();
    }
    function step(delta) { refresh(); set(Math.round((level + delta) * 100) / 100); }

    readonly property bool watched: Shell.sidebarOpen && !Session.locked
    onWatchedChanged: if (watched) refresh()

    Process {
        id: reader
        command: ["brightnessctl", "-m", "-c", "backlight", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(",");
                if (f.length >= 5 && Number(f[4]) > 0) {
                    root.device = f[0];
                    root.max = Number(f[4]);
                    root.level = Number(f[2]) / root.max;
                    root.available = true;
                }
            }
        }
    }
    // Read on demand, in place (a sysfs attribute is a few bytes).
    FileView {
        id: current
        path: root.device ? "/sys/class/backlight/" + root.device + "/brightness" : ""
        preload: false
        blockAllReads: true
        printErrors: false
    }
    Component.onCompleted: refresh()
    Timer { interval: 15000; running: root.watched && root.device !== ""; repeat: true; onTriggered: root.refresh() }
}
