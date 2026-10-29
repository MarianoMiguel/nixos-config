pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The panel's backlight through brightnessctl. changed() feeds the island.
Singleton {
    id: root

    property real level: 0.5
    property bool available: false
    signal changed()

    function refresh() { reader.running = true; }
    function set(v) {
        level = Math.max(0.01, Math.min(1, v));
        Quickshell.execDetached(["brightnessctl", "-q", "set", Math.round(level * 100) + "%"]);
        changed();
    }
    function step(delta) { set(Math.round((level + delta) * 100) / 100); }

    Process {
        id: reader
        command: ["brightnessctl", "-m", "-c", "backlight", "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(",");
                if (f.length >= 5) { root.level = Number(f[2]) / Math.max(1, Number(f[4])); root.available = true; }
            }
        }
    }
    Component.onCompleted: refresh()
    Timer { interval: 15000; running: true; repeat: true; onTriggered: root.refresh() }
}
