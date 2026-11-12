pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// The notification server. Live notifications group by app, newest first.
// posted() feeds the island's peek. Quiet (a focus session, Do not disturb,
// or the schedule) holds everything but critical ones, which the preferences
// may hold too. Every app that notifies is remembered with its name and icon
// and its rules: off drops its notifications, banners peek, sound chimes.
// Dismissed notifications stay a day in history. Clearing is undoable.
// Preferences live in ~/.config/folio/notifications.json (the harness: its
// runtime directory). fixture() shows test data to the Settings page only.
Singleton {
    id: root

    property var hidden: ({})
    property var times: ({})
    property var history: []
    property var forgotten: ({})            // ids cleared from history: not remembered when they close
    readonly property bool quiet: Focus.active || Focus.dnd || scheduled
    readonly property string quietReason: Focus.active ? "focus" : Focus.dnd ? "dnd" : scheduled ? "schedule" : ""
    readonly property var live: server.trackedNotifications.values.filter(n => !root.hidden[n.id] && root.allows(root.keyOf(n)))
    readonly property int count: live.length

    signal posted(var notification)

    readonly property var groups: {
        const by = {};
        for (const n of live) {
            const key = root.keyOf(n);
            (by[key] = by[key] || []).push(n);
        }
        return Object.keys(by).map(app => {
            const items = by[app].sort((a, b) => root.timeOf(b) - root.timeOf(a));
            return { "app": app, "items": items, "latest": root.timeOf(items[0]), "icon": items[0].appIcon || "" };
        }).sort((a, b) => b.latest - a.latest);
    }

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true
        bodyMarkupSupported: false
        onNotification: n => {
            const key = root.keyOf(n);
            root.see(n, key);
            const rule = root.rule(key);
            if (!rule.allow) return;                // off: never tracked, so it is dropped
            n.tracked = true;
            const t = Object.assign({}, root.times);
            t[n.id] = Date.now();
            root.times = t;
            n.closed.connect(() => root.remember(n));
            if (root.holds(n)) return;
            if (rule.banners) root.posted(n);
            if (rule.sound) root.chime(n);
        }
    }

    function keyOf(n) { return n.appName || n.desktopEntry || "Notifications"; }
    function timeOf(n) { return times[n.id] || Date.now(); }
    function ago(n) {
        const s = (Date.now() - timeOf(n)) / 1000;
        if (s < 60) return "now";
        if (s < 3600) return Math.floor(s / 60) + " min";
        if (s < 86400) return Math.floor(s / 3600) + " h";
        return Math.floor(s / 86400) + " d";
    }
    function remember(n) {
        if (forgotten[n.id]) return;
        const cut = Date.now() - 86400000;
        history = [{ "app": n.appName, "summary": n.summary, "body": n.body, "time": timeOf(n) }].concat(history.filter(h => h.time > cut)).slice(0, 200);
    }
    function invoke(n, action) { action.invoke(); }

    // Dismiss with undo: hidden now, gone when the toast times out.
    function dismiss(list, label) {
        const ids = list.map(n => n.id);
        const h = Object.assign({}, hidden);
        for (const id of ids) h[id] = true;
        hidden = h;
        Toasts.undo(label || (ids.length === 1 ? "Notification dismissed" : ids.length + " notifications cleared"), () => {
            for (const n of server.trackedNotifications.values) if (ids.indexOf(n.id) >= 0) n.dismiss();
            root.unhide(ids);
        }, () => root.unhide(ids), "bell");
    }
    function unhide(ids) { const h = Object.assign({}, hidden); for (const id of ids) delete h[id]; hidden = h; }
    function clearAll() { if (live.length) dismiss(live.slice()); }

    // Clear history: the day's history and everything still waiting, undoable.
    function clearHistory() {
        if (fx) {
            const was = { "waiting": fx.waiting, "recent": fx.recent };
            patch({ "waiting": 0, "recent": 0 });
            Toasts.undo(clearedLabel(was.waiting + was.recent), () => {}, () => { if (root.fx) root.patch(was); }, "bell");
            return;
        }
        const kept = history.slice();
        const ids = live.map(n => n.id);
        if (!kept.length && !ids.length) return;
        history = [];
        const h = Object.assign({}, hidden), f = Object.assign({}, forgotten);
        for (const id of ids) { h[id] = true; f[id] = true; }
        hidden = h;
        forgotten = f;
        Toasts.undo(clearedLabel(kept.length + ids.length), () => {
            for (const n of server.trackedNotifications.values.slice()) if (ids.indexOf(n.id) >= 0) n.dismiss();
            root.unhide(ids);
        }, () => {
            root.history = root.history.concat(kept).slice(0, 200);
            const r = Object.assign({}, root.forgotten);
            for (const id of ids) delete r[id];
            root.forgotten = r;
            root.unhide(ids);
        }, "bell");
    }
    function clearedLabel(n) { return n === 1 ? "1 notification cleared" : n + " notifications cleared"; }

    // ------------------------------------------------------------ quiet
    // Minutes after midnight, for the schedule.
    property int minute: minuteNow()
    function minuteNow() { const d = new Date(); return d.getHours() * 60 + d.getMinutes(); }
    Timer { interval: 15000; repeat: true; running: true; onTriggered: root.minute = root.minuteNow() }
    readonly property bool scheduled: inWindow(prefs.schedule, minute)
    // A window that crosses midnight (22:00 to 07:00) wraps; equal ends mean none.
    function inWindow(s, m) {
        if (!s || !s.on || s.from === s.to) return false;
        return s.from < s.to ? (m >= s.from && m < s.to) : (m >= s.from || m < s.to);
    }
    function holds(n) { return quiet && !(prefs.critical !== false && n.urgency === NotificationUrgency.Critical); }

    // ------------------------------------------------------------ preferences
    readonly property var appDefaults: ({ "allow": true, "banners": true, "sound": true })
    property var prefs: ({ "schedule": { "on": false, "from": 1320, "to": 420 }, "critical": true, "apps": {} })
    function rule(key) { return Object.assign({}, appDefaults, prefs.apps[key] || {}); }
    function allows(key) { const a = prefs.apps[key]; return !a || a.allow !== false; }

    // Remember the app: its name, an icon that lasts (the desktop entry's
    // before a temporary image), how many it sent and when it last did.
    function see(n, key) {
        const apps = Object.assign({}, prefs.apps);
        const was = apps[key] || {};
        apps[key] = Object.assign({}, was, {
            "name": key, "icon": iconOf(n) || was.icon || "", "entry": n.desktopEntry || was.entry || "",
            "count": (was.count || 0) + 1, "seen": Date.now()
        });
        write(Object.assign({}, prefs, { "apps": apps }));
    }
    function iconOf(n) {
        const byId = n.desktopEntry ? DesktopEntries.byId(n.desktopEntry) : null;
        if (byId && byId.icon) return byId.icon;
        const own = n.appIcon || "";
        if (own && !/^(file:\/\/)?\/tmp\//.test(own)) return own;
        const guess = n.appName ? DesktopEntries.heuristicLookup(n.appName) : null;
        return guess && guess.icon ? guess.icon : "";
    }

    readonly property string dir: Sys.harness ? Quickshell.env("XDG_RUNTIME_DIR") + "/folio"
        : (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/folio"
    function write(p) { prefs = p; saveLater.restart(); }
    Timer { id: saveLater; interval: 400; onTriggered: file.setText(JSON.stringify(root.prefs, null, 2) + "\n") }
    Process { running: true; command: ["mkdir", "-p", root.dir] }
    FileView {
        id: file
        path: root.dir + "/notifications.json"
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.prefs = {
                    "schedule": Object.assign({}, root.prefs.schedule, s.schedule || {}),
                    "critical": s.critical !== false,
                    // Apps seen before the file loaded keep their count.
                    "apps": Object.assign({}, s.apps || {}, root.prefs.apps)
                };
            } catch (e) { console.warn("Notifs: unreadable", path, e); }
        }
    }

    // ------------------------------------------------------------ sound
    // Folio's notification sound ("message" for chat apps), or the app's own
    // sound-file; never when the app asks for silence. Sounds keeps it to one
    // in a burst, holds it while quiet (a critical one plays through) and
    // plays it at the effects volume, through Sys.
    function chime(n) {
        const h = n.hints || {};
        if (h["suppress-sound"] === true) return;
        const own = String(h["sound-file"] || "").replace(/^file:\/\//, "");
        Sounds.play(Sounds.chat(n) ? "message" : "notification", { "urgent": n.urgency === NotificationUrgency.Critical, "file": own });
    }

    // ------------------------------------------------------------ the Settings page
    // What the page shows and changes: the live preferences, or a fixture's
    // (whose changes stay in the fixture: no file, no Focus, no history).
    property var fx: null
    property string openApp: ""             // the app row open on the page
    readonly property var view: fx ? fx.prefs : prefs
    readonly property bool dndOn: fx ? fx.dnd : Focus.dnd
    readonly property bool focusOn: fx ? fx.focusEnds > Date.now() : Focus.active
    readonly property real focusEnds: fx ? fx.focusEnds : Focus.endsAt
    readonly property int waiting: fx ? fx.waiting : live.length
    readonly property int recent: fx ? fx.recent : history.length
    readonly property var apps: {
        const src = view.apps || {};
        return Object.keys(src).map(k => Object.assign({ "name": k, "icon": "", "count": 0, "seen": 0 }, appDefaults, src[k], { "key": k }))
            .sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
    }

    function patch(values) { fx = Object.assign({}, fx, values); }
    function change(key, value) {
        const p = Object.assign({}, view);
        p[key] = value;
        if (fx) patch({ "prefs": p }); else write(p);
    }
    function setDnd(on) { if (fx) patch({ "dnd": on }); else Focus.setDnd(on); }
    function startFocus(minutes) { if (fx) patch({ "focusEnds": Date.now() + minutes * 60000 }); else Focus.start(minutes); }
    function stopFocus() { if (fx) patch({ "focusEnds": 0 }); else Focus.stop(); }
    function setSchedule(values) { change("schedule", Object.assign({}, view.schedule, values)); }
    function setCritical(on) { change("critical", on); }
    function setApp(key, field, value) {
        if (!(field in appDefaults)) return;
        const apps = Object.assign({}, view.apps);
        const a = Object.assign({ "name": key }, apps[key] || {});
        a[field] = value;
        apps[key] = a;
        change("apps", apps);
    }
    function since(t) {
        if (!t) return "";
        const s = (Date.now() - t) / 1000;
        if (s < 60) return "just now";
        if (s < 3600) return Math.floor(s / 60) + " min ago";
        if (s < 86400) return Math.floor(s / 3600) + " h ago";
        return Math.floor(s / 86400) + " d ago";
    }

    function makeFixture(name) {
        const now = Date.now();
        const app = (n, icon, rules, minutes, count) => [n, Object.assign({ "name": n, "icon": icon, "count": count, "seen": now - minutes * 60000 }, rules)];
        let list = [];
        if (name === "normal") list = [
            app("Slack", "slack", {}, 3, 412),
            app("Google Chrome", "google-chrome", { "sound": false }, 25, 96),
            app("Spotify", "spotify", { "banners": false, "sound": false }, 180, 57),
            app("Telegram Desktop", "telegram", {}, 8, 230),
            app("Beeper", "beepertexts", {}, 60 * 26, 18),
            app("Thunderbird", "thunderbird", { "allow": false }, 60 * 24 * 3, 7),
            app("Calendar", "org.gnome.Calendar", {}, 50, 12),
            app("notify-send", "", { "banners": false }, 60 * 24 * 6, 2)
        ];
        else if (name === "stress") {
            const long = [
                ["Slack — #infra-alerts-production-eu-west-1-critical (Monarch Health Engineering workspace)", "slack"],
                ["Google Chrome — Calendar for mariano.miguel@monarchmd.com · Profile 7 (Work, Beta channel)", "google-chrome"],
                ["org.freedesktop.FileManager1 — Copying 1,204 files from “Backups (external drive)” to home", ""],
                ["Telegram Desktop — Familia Miguel 🧉 (muted until further notice, except mentions and replies)", "telegram"]
            ];
            const short = ["Beeper", "Calendar", "Discord", "Firefox", "Geary", "GIMP", "Kate", "Krita", "Nautilus", "Obsidian", "OBS Studio", "Signal", "Spotify", "Steam", "Thunderbird", "Tailscale", "Visual Studio Code", "VLC", "Zoom", "1Password"];
            const icons = ["beepertexts", "org.gnome.Calendar", "discord", "firefox", "org.gnome.Geary", "gimp", "kate", "krita", "org.gnome.Nautilus", "obsidian", "com.obsproject.Studio", "signal-desktop", "spotify", "steam", "thunderbird", "tailscale", "code", "vlc", "Zoom", "1password"];
            for (let i = 0; i < long.length; i++) list.push(app(long[i][0], long[i][1], { "allow": i !== 2, "sound": i % 2 === 0 }, i * 7 + 1, 1200 + i));
            for (let i = 0; i < 44; i++) {
                const k = i % short.length;
                const n = i < short.length ? short[k] : short[k] + " (" + (Math.floor(i / short.length) + 1) + ")";
                list.push(app(n, icons[k], { "allow": i % 9 !== 4, "banners": i % 3 !== 1, "sound": i % 4 !== 2 }, i * 97, i * 13 + 1));
            }
        }
        const apps = {};
        for (const a of list) apps[a[0]] = a[1];
        return {
            "normal": { "prefs": { "schedule": { "on": true, "from": 1320, "to": 420 }, "critical": true, "apps": apps }, "dnd": false, "focusEnds": 0, "waiting": 3, "recent": 14 },
            "stress": { "prefs": { "schedule": { "on": true, "from": 1425, "to": 1410 }, "critical": false, "apps": apps }, "dnd": true, "focusEnds": now + 7199000, "waiting": 1312, "recent": 200 },
            "empty": { "prefs": { "schedule": { "on": false, "from": 1320, "to": 420 }, "critical": true, "apps": {} }, "dnd": false, "focusEnds": 0, "waiting": 0, "recent": 0 }
        }[name] || null;
    }

    IpcHandler {
        target: "notifications"
        // normal | stress | empty for the Settings page; "" (anything else) is live.
        function fixture(name: string): void { root.openApp = ""; root.fx = root.makeFixture(name); }
        // An app's rule: field allow | banners | sound (the fixture's when one is set).
        function app(name: string, field: string, on: bool): void { root.setApp(name, field, on); }
        // Open (or close, "") an app's row on the page.
        function open(name: string): void { root.openApp = name; }
        function dnd(on: bool): void { root.setDnd(on); }
        // Schedule from HH:MM to HH:MM; on false turns it off.
        function schedule(on: bool, from: string, to: string): void {
            const m = s => { const p = String(s).split(":"); return (Number(p[0]) || 0) * 60 + (Number(p[1]) || 0); };
            root.setSchedule({ "on": on, "from": m(from), "to": m(to) });
        }
        function critical(on: bool): void { root.setCritical(on); }
        function clear(): void { root.clearHistory(); }
        function state(): string {
            return JSON.stringify({
                "fixture": !!root.fx, "quiet": root.quiet, "reason": root.quietReason, "scheduled": root.scheduled,
                "waiting": root.waiting, "recent": root.recent, "live": root.live.length,
                "file": file.path, "prefs": root.view
            });
        }
    }
}
