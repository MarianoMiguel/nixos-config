pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// AI usage limits from CodexBar (`codexbar usage --json`): once at start,
// then only while the sidebar (the one place that shows them) is open and
// the screen unlocked: on opening when the last ask is a minute old, and
// every minute while it stays open. Each ask is a network call and about a
// CPU-second, so a closed sidebar asks nothing.
// rows: [{provider, name, window, used (0..1+), resetsAt (ms)}], one per rate
// window. Providers that fail are left out; available is false when none
// answered (or codexbar is missing), and a miss keeps the last good rows for
// ten minutes.
Singleton {
    id: root

    property var rows: []
    property real updated: 0
    readonly property bool available: rows.length > 0

    property real asked: 0
    function refresh() { if (!proc.running) { asked = Date.now(); proc.running = true; } }
    readonly property bool watched: Shell.sidebarOpen && !Session.locked
    onWatchedChanged: if (watched && Date.now() - asked >= 60000) refresh()
    Component.onCompleted: refresh()

    function windowLabel(min) {
        if (min === 10080) return "week";
        if (min === 1440) return "day";
        if (min % 1440 === 0) return (min / 1440) + " d";
        if (min % 60 === 0) return (min / 60) + " h";
        return min + " m";
    }
    // "resets 01:10" within a day, else "resets Mon".
    function resetLabel(ms, now) {
        if (!ms) return "";
        const d = new Date(ms);
        if (ms - (now || Date.now()) < 86400000)
            return "resets " + String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
        return "resets " + ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getDay()];
    }

    function parse(text) {
        let list;
        try { list = JSON.parse(text); } catch (e) { return null; }
        if (!Array.isArray(list)) list = [list];
        const out = [];
        for (const e of list) {
            const u = e && e.usage;
            if (!u) continue;
            const id = e.provider || (u.identity && u.identity.providerID) || "";
            const name = id.charAt(0).toUpperCase() + id.slice(1);
            const add = (w, label) => {
                if (!w || w.usedPercent === undefined) return;
                out.push({ "provider": id, "name": label || name, "window": windowLabel(w.windowMinutes || 0),
                           "used": w.usedPercent / 100, "resetsAt": w.resetsAt ? Date.parse(w.resetsAt) : 0 });
            };
            add(u.primary); add(u.secondary); add(u.tertiary);
            for (const x of u.extraRateWindows || [])
                add(x.window, (x.title || "").replace(/ only$/, "") || name);
        }
        return out;
    }

    Process {
        id: proc
        command: ["sh", "-c", "command -v codexbar >/dev/null && exec timeout 45 codexbar usage --json --source oauth --provider both"]
        stdout: StdioCollector {
            onStreamFinished: {
                const r = root.parse(text);
                if (r && r.length) { root.rows = r; root.updated = Date.now(); }
                else if (Date.now() - root.updated > 600000) root.rows = [];
            }
        }
    }
    Timer { interval: 60000; running: root.watched; repeat: true; onTriggered: root.refresh() }
}
