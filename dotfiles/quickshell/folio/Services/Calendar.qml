pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Events from khal, when it is configured with at least one calendar;
// otherwise connected stays false and events empty. Refreshes every 10 min.
// khal prints dates in its configured format, so the format is learned from
// `khal printformats` (it prints 2013-12-21 in each one).
// events: [{date: "YYYY-MM-DD", start: "15:00", end: "15:45", allDay, title, location, at (ms)}]
Singleton {
    id: root

    property bool connected: false
    property var events: []
    property var parser: null       // {re, order, year2} from the long date format
    property string sample: ""

    function refresh() { if (!probe.running && !list.running) probe.running = true; }
    function ymd(d) { return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); }
    function on(date) { return events.filter(e => e.date === date); }

    // A regex for a strftime sample of 2013-12-21; null if it is not numeric.
    function learn(s) {
        let t = s;
        const year2 = t.indexOf("2013") < 0;
        t = year2 ? t.replace("13", "\x01") : t.replace("2013", "\x01");
        t = t.replace("21", "\x02").replace("12", "\x03");
        if (t.indexOf("\x01") < 0 || t.indexOf("\x02") < 0 || t.indexOf("\x03") < 0) return null;
        const order = ["\x01", "\x02", "\x03"].sort((a, b) => t.indexOf(a) - t.indexOf(b)).map(c => ({ "\x01": "y", "\x02": "d", "\x03": "m" })[c]);
        const re = t.replace(/[.*+?^${}()|[\]\\\/]/g, "\\$&").replace("\x01", year2 ? "(\\d{2})" : "(\\d{4})").replace("\x02", "(\\d{1,2})").replace("\x03", "(\\d{1,2})");
        return { "re": new RegExp("^" + re + "$"), "order": order, "year2": year2, "template": t };
    }
    function parseDate(s) {
        const m = parser && parser.re.exec(s.trim());
        if (!m) return "";
        const v = {};
        parser.order.forEach((k, i) => v[k] = Number(m[i + 1]));
        if (parser.year2) v.y += 2000;
        return v.y + "-" + String(v.m).padStart(2, "0") + "-" + String(v.d).padStart(2, "0");
    }
    function formatDate(d) {
        return parser.template.replace("\x01", parser.year2 ? String(d.getFullYear() % 100).padStart(2, "0") : d.getFullYear())
            .replace("\x02", String(d.getDate()).padStart(2, "0")).replace("\x03", String(d.getMonth() + 1).padStart(2, "0"));
    }
    function minutes(t) {
        const m = /(\d{1,2})[:.](\d{2})\s*([AaPp])?/.exec(t || "");
        if (!m) return -1;
        let h = Number(m[1]) % (m[3] ? 12 : 24);
        if (m[3] && m[3].toLowerCase() === "p") h += 12;
        return h * 60 + Number(m[2]);
    }

    // Is khal set up, and in which date format does it speak?
    Process {
        id: probe
        command: ["sh", "-c", "command -v khal >/dev/null && khal printcalendars 2>/dev/null | grep -q . && khal printformats 2>/dev/null | sed -n 's/^longdateformat: //p'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim();
                root.parser = s ? root.learn(s) : null;
                root.connected = s !== "";
                if (!root.connected) { root.events = []; return; }
                // From the first Monday on the month grid, ten weeks on.
                const now = new Date(), first = new Date(now.getFullYear(), now.getMonth(), 1);
                first.setDate(1 - (first.getDay() + 6) % 7);
                list.command = ["khal", "list", "--once", "-df", "", "-f",
                    "{start-date-long}\t{start-time}\t{end-time}\t{title}\t{location}",
                    root.parser ? root.formatDate(first) : "today", "70d"];
                list.running = true;
            }
        }
    }
    Process {
        id: list
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const f = line.split("\t");
                    if (f.length < 4) continue;
                    const date = root.parseDate(f[0]);
                    if (!date) continue;
                    const mins = root.minutes(f[1]);
                    const at = new Date(date + "T00:00:00").getTime() + Math.max(0, mins) * 60000;
                    out.push({ "date": date, "start": f[1], "end": f[2], "allDay": f[1] === "", "title": f[3], "location": f[4] || "", "at": at });
                }
                root.events = out.sort((a, b) => a.at - b.at);
            }
        }
    }
    Timer { interval: 600000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
}
