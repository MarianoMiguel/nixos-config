import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import "Search.js" as Search

// The launcher: a search sheet in the middle of the focused screen. Apps and
// their actions, system actions, a calculator and unit conversions, files in
// the home folder, emoji, clipboard history and the web, ranked together,
// with a Quick Look preview of the selection. Prefixes narrow it: "clip ",
// "f " (files), ":" or "emoji ". It grows from the centre on a spring, every
// time: something opened this often should be quick, never printed in.
Scope {
    id: root

    readonly property bool open: Shell.launcherOpen
    readonly property bool harness: (Quickshell.env("FOLIO_HARNESS") || "") !== ""

    property string query: ""
    property string scope: ""               // "", "clipboard" ("clip "), "files" ("f "), "emoji" (":")
    property var rows: []                   // what the list draws: captions and results
    property var items: []                  // the results alone, in order
    property int sel: 0
    property bool actionsMode: false        // the keyboard is in the preview's actions
    property int actionIndex: 0
    property bool ctrlHeld: false
    property bool glide: false              // the selection springs only on arrow keys
    property real now: Date.now()
    property point pointer: Qt.point(-1, -1)
    property string lastRun: ""             // what the last action ran (or would have)

    // Fixtures stand in for the installed apps, the clipboard and the files.
    property var fakeApps: null
    property var fakeClips: null
    property var fakeFiles: null

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property var scopes: ({
        "clipboard": { "title": "Clipboard", "hint": "Search the clipboard" },
        "files": { "title": "Files", "hint": "Search files in your home folder" },
        "emoji": { "title": "Emoji", "hint": "Search emoji by name or word" }
    })

    readonly property var current: items.length ? items[Math.max(0, Math.min(sel, items.length - 1))] : null
    readonly property var actions: current ? actionsFor(current) : []

    // ---- Running things. In the harness, actions are recorded, not run.

    function act(label, fn, safe) {
        lastRun = label;
        if (!harness || safe) fn();
    }
    function sh(cmd) { act(cmd.join(" "), () => Quickshell.execDetached(cmd)); }
    function close() { Shell.launcherOpen = false; }

    function launch(entry, action) {
        const label = "launch " + entry.id + (action ? " · " + action.name : "");
        if (entry.fake) act(label, () => {});
        else act(label, () => Apps.launch(entry, action));
        close();
    }
    function copy(text) {
        act("wl-copy " + Search.oneLine(text).slice(0, 80), () => Clipboard.copy(text), true);
        close();
    }
    function web(q) {
        sh(["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(q)]);
        close();
    }
    function forget(it) {
        if (fakeClips) {
            fakeClips = fakeClips.filter(c => c.text !== it.text);
        } else {
            const index = Clipboard.items.findIndex(c => c.text === it.text);
            const entry = { "text": it.text, "time": it.time };
            Clipboard.remove(it.text);
            Toasts.undo("Forgot a clipboard entry", null, () => Clipboard.restore(entry, index), "note");
        }
        lastRun = "forget clipboard entry";
        const keep = sel;
        rebuild();
        sel = Math.min(keep, items.length - 1);
    }
    // Files open in their default app; Show in Files selects the file in the
    // file manager (FileManager1), or opens its folder when there is none.
    function fileUri(path) { return "file://" + path.split("/").map(encodeURIComponent).join("/").replace(/'/g, "%27"); }
    function openFile(it) {
        act("xdg-open " + it.path, () => Quickshell.execDetached(["xdg-open", it.path]));
        close();
    }
    function showFile(it) {
        const dir = it.path.slice(0, Math.max(1, it.path.lastIndexOf("/")));
        act("show in files " + it.path, () => Quickshell.execDetached(["sh", "-c",
            "gdbus call --session --dest org.freedesktop.FileManager1 --object-path /org/freedesktop/FileManager1 " +
            "--method org.freedesktop.FileManager1.ShowItems \"['$1']\" '' >/dev/null 2>&1 || xdg-open \"$2\"", "sh", fileUri(it.path), dir]));
        close();
    }
    // Copied emoji go to the top of the picker until the shell restarts.
    property var emojiRecent: []
    function copyEmoji(it, text) {
        emojiRecent = [it.char].concat(emojiRecent.filter(c => c !== it.char)).slice(0, 16);
        copy(text);
        Toasts.show(text === it.char ? "Copied " + it.char + "  " + it.name : "Copied “" + Search.oneLine(text).slice(0, 40) + "”", { "icon": "check" });
    }
    function runItem(it, index) {
        const list = actionsFor(it);
        const a = list[Math.max(0, Math.min(index || 0, list.length - 1))];
        if (a) a.run();
    }

    // ---- What each result can do; the first is what Enter does.

    function entryActions(entry) {
        return Array.from(entry.actions || []).map(a => ({ "label": a.name, "run": () => root.launch(entry, a) }));
    }
    function actionsFor(it) {
        switch (it.kind) {
        case "app":
            return [{ "label": "Open", "run": () => launch(it.entry, null) }].concat(entryActions(it.entry));
        case "appAction":
            return [{ "label": it.action.name, "run": () => launch(it.entry, it.action) },
                    { "label": "Open " + it.entry.name, "run": () => launch(it.entry, null) }]
                .concat(entryActions(it.entry).filter(a => a.label !== it.action.name));
        case "system":
            return [{ "label": it.verb, "run": it.run }];
        case "calc":
            return [{ "label": "Copy " + it.calc.text, "run": () => copy(it.calc.text) },
                    { "label": "Copy " + it.calc.expression + " = " + it.calc.text, "run": () => copy(it.calc.expression + " = " + it.calc.text) }];
        case "clip":
            return [{ "label": "Copy", "run": () => copy(it.text) },
                    { "label": "Forget", "danger": true, "run": () => forget(it) }];
        case "unit":
            return [{ "label": "Copy " + it.calc.text, "run": () => copy(it.calc.text) },
                    { "label": "Copy " + it.calc.number, "run": () => copy(it.calc.number) },
                    { "label": "Copy " + it.calc.expression + " = " + it.calc.text, "run": () => copy(it.calc.expression + " = " + it.calc.text) }];
        case "file":
            return [{ "label": "Open", "run": () => openFile(it) },
                    { "label": "Show in Files", "run": () => showFile(it) },
                    { "label": "Copy path", "run": () => copy(it.path) }];
        case "emoji":
            return [{ "label": "Copy " + it.char, "run": () => copyEmoji(it, it.char) },
                    { "label": "Copy “" + it.name + "”", "run": () => copyEmoji(it, it.name) },
                    { "label": "Copy " + Search.codepoints(it.char), "run": () => copyEmoji(it, Search.codepoints(it.char)) }];
        case "web":
            return [{ "label": "Search DuckDuckGo", "run": () => web(it.query) }];
        }
        return [];
    }
    function verb(it) {
        if (!it) return "";
        return { "app": "Open", "appAction": "Open", "calc": "Copy", "unit": "Copy", "clip": "Copy", "emoji": "Copy", "file": "Open", "web": "Search" }[it.kind] || it.verb || "Run";
    }

    // ---- Sources

    function apps() { return fakeApps || Apps.all; }
    function clips() { return fakeClips || Clipboard.items; }

    function appItem(e, score) {
        const used = Apps.usage[e.id] || 0;
        return { "kind": "app", "entry": e, "title": e.name, "subtitle": e.genericName || e.comment || "",
                 "icon": e.icon || "", "genericName": e.genericName || "", "description": e.comment || "", "score": score || 0,
                 "meta": e.id + (used ? " · opened " + used + (used === 1 ? " time" : " times") : "") };
    }
    function clipItem(c) {
        return { "kind": "clip", "text": c.text, "time": c.time, "glyph": "note",
                 "title": Search.oneLine(c.text).slice(0, 240), "subtitle": Search.ago(c.time, now) };
    }
    function fileItem(f, score) {
        const type = Search.fileType(f.name, f.dir);
        const folder = Search.tilde(f.path.slice(0, Math.max(1, f.path.lastIndexOf("/"))), home);
        return { "kind": "file", "path": f.path, "name": f.name, "dir": f.dir, "mtime": f.mtime, "size": f.size, "type": type,
                 "glyph": type.glyph, "title": f.name, "subtitle": folder, "folder": folder, "score": score || 0,
                 "description": "Modified " + Search.ago(f.mtime * 1000, now) + (f.dir ? "" : " · " + Search.bytes(f.size)),
                 "meta": Search.tilde(f.path, home) };
    }
    function emojiItem(e, quiet) {
        const name = e.name.charAt(0).toUpperCase() + e.name.slice(1);
        return { "kind": "emoji", "char": e.char, "emoji": e.char, "name": e.name, "title": name,
                 "subtitle": quiet ? "" : (emojiGroups[e.group] || ""), "group": emojiGroups[e.group] || "", "keywords": e.keywords };
    }

    // The dock's pinned apps ("google-chrome" finds com.google.Chrome).
    function pinnedApps() {
        const all = apps();
        const norm = s => String(s || "").toLowerCase().replace(/[^a-z0-9]/g, "");
        return (Settings.get("dock.pinned") || []).map(p => all.find(e => norm(e.id) === norm(p) || norm(e.id).endsWith(norm(p)))).filter(e => e);
    }
    // Most used first, then the dock's pinned apps; the alphabet only fills in
    // on a fresh install.
    function frequent(n) {
        const all = apps();
        const usage = Apps.usage;
        const used = all.filter(e => (usage[e.id] || 0) > 0).sort((a, b) => usage[b.id] - usage[a.id]);
        const pinned = pinnedApps();
        const out = [];
        const add = list => { for (const e of list) if (out.length < n && out.indexOf(e) < 0) out.push(e); };
        add(used.concat(pinned));
        if (out.length < 3) add(all);
        return out;
    }

    function appResults(q) {
        const limit = fakeApps ? 30 : 10;
        const found = (fakeApps ? fakeApps.filter(e => Apps.score(e, q) > 0).sort((a, b) => Apps.score(b, q) - Apps.score(a, q)) : Apps.search(q, limit))
            .slice(0, limit).map(e => appItem(e, Apps.score(e, q)));
        // Desktop actions that match well stand on their own ("incognito");
        // the dock's apps and the most used go first.
        const named = [];
        const pinned = pinnedApps();
        if (q.length >= 3) {
            for (const e of apps()) {
                for (const a of Array.from(e.actions || [])) {
                    const s = Search.score(a.name, "", q) + Math.min(20, (Apps.usage[e.id] || 0) * 2) + (pinned.indexOf(e) >= 0 ? 4 : 0);
                    if (s >= 60) named.push({ "kind": "appAction", "entry": e, "action": a, "title": a.name, "subtitle": e.name, "appName": e.name,
                                              "icon": a.icon || e.icon || "", "description": e.comment || "", "meta": e.id, "score": s - 5 });
                }
            }
        }
        return found.concat(named.sort((a, b) => b.score - a.score).slice(0, 4)).sort((a, b) => b.score - a.score);
    }

    function systemActions() {
        const sys = (id, title, glyph, words, verb, subtitle, description, run, meta) =>
            ({ "kind": "system", "id": id, "title": title, "glyph": glyph, "words": words, "verb": verb, "subtitle": subtitle, "description": description, "run": run, "meta": meta || "" });
        const until = m => Qt.formatTime(new Date(Date.now() + m * 60000), "HH:mm");
        const focusNote = Focus.active ? " Replaces the session running now (" + Focus.clock + " left)." : "";
        const list = [
            sys("lock", "Lock", "lock", "lock screen away", "Lock", "Session",
                "Locks the screen now. Your windows stay as they are.",
                () => { act("Power.lock()", () => Power.lock()); close(); }, "Folio lock screen"),
            sys("hibernate", "Hibernate", "battery", "sleep suspend hibernate", "Hibernate", "Session",
                "Locks first, then saves everything to disk and powers off. You come back to exactly this.",
                () => { act("Power.hibernate()", () => Power.hibernate()); close(); }, "systemctl hibernate"),
            sys("reboot", "Restart", "reload", "restart reboot", "Restart", "In 5 s",
                "Restarts in 5 s; you can cancel.",
                () => { act("Power.reboot()", () => Power.reboot()); close(); }, "systemctl reboot"),
            sys("poweroff", "Shut down", "power", "shut down shutdown power off poweroff halt turn off", "Shut down", "In 5 s",
                "Shuts down in 5 s; you can cancel.",
                () => { act("Power.poweroff()", () => Power.poweroff()); close(); }, "systemctl poweroff"),
            sys("logout", "Log out", "user", "log out logout sign out exit quit session", "Log out", "In 5 s",
                "Ends the session in 5 s; you can cancel. Open windows close.",
                () => { act("Power.logout()", () => Power.logout()); close(); }, "niri msg action quit"),
            sys("focus25", "Focus for 25 minutes", "bell", "focus do not disturb dnd pomodoro silence quiet 25", "Start", "Until " + until(25),
                "Silences notifications until " + until(25) + "." + focusNote,
                () => { act("Focus.start(25)", () => Focus.start(25)); close(); }, "Focus · 25 min"),
            sys("focus50", "Focus for 50 minutes", "bell", "focus do not disturb dnd silence quiet 50", "Start", "Until " + until(50),
                "Silences notifications until " + until(50) + "." + focusNote,
                () => { act("Focus.start(50)", () => Focus.start(50)); close(); }, "Focus · 50 min"),
            sys("dark", "Dark mode", "moon", "dark mode night theme appearance", "Switch", Theme.dark ? "Current" : "Appearance",
                Theme.dark ? "The desktop is already dark." : "Night paper and moonlit plates. Apps follow.",
                () => { act("Theming.set(dark)", () => Theming.set({ "mode": "dark" }, "dark mode"), true); close(); }, "azure-folio set --mode dark"),
            sys("light", "Light mode", "sun", "light mode day theme appearance", "Switch", Theme.dark ? "Appearance" : "Current",
                Theme.dark ? "Ink on paper. Apps follow." : "The desktop is already light.",
                () => { act("Theming.set(light)", () => Theming.set({ "mode": "light" }, "light mode"), true); close(); }, "azure-folio set --mode light"),
            sys("appearance", "Appearance…", "palette", "appearance settings theme ink mode wallpaper plates motion look", "Open", "Settings",
                "Mode, ink, plates and motion, in one place.",
                () => { act("Shell.openAppearance()", () => Shell.openAppearance(), true); }, "Folio · Appearance"),
            sys("night", NightLight.active ? "Turn off Night light" : "Night light", "moon", "night light warm blue light evening eyes shift",
                NightLight.active ? "Pause" : "Turn on", NightLight.schedule === "off" ? "Off" : (NightLight.active ? "On" : "Scheduled"),
                NightLight.active ? "Pauses warm colors until the schedule next changes." : "Warmer colors. Change the schedule in Settings › Displays.",
                () => { act("NightLight", () => {
                    if (NightLight.active) NightLight.snoozed = true;
                    else if (NightLight.due) NightLight.snoozed = false;
                    else Settings.set("night.schedule", "always");
                }, true); close(); }, "Settings › Displays"),
            sys("identify", "Identify displays", "display", "identify displays monitors screens which name", "Show", "Displays",
                "Shows each display's name on it for a moment.", () => { act("Outputs.identify()", () => Outputs.identify(), true); close(); }, "Settings › Displays"),
            sys("layout", "Next display layout", "display", "display layout arrangement monitors switch cycle docked mirror", "Switch", Outputs.active ? Outputs.active.name : "Displays",
                Outputs.current.length > 1 ? "Switches to the next layout saved for these displays." : "Only one layout is saved for these displays.",
                () => { act("Outputs.cycle()", () => Outputs.cycle()); close(); }, "Settings › Displays")
        ];
        // Each Settings page, by name and by what is on it.
        for (const p of [["displays", "Displays", "display", "monitor screen resolution scale refresh arrange external"],
                         ["sound", "Sound", "speaker", "audio volume output input microphone speakers headphones mixer"],
                         ["network", "Network", "wifi", "wifi wi-fi wireless ethernet vpn tailscale internet"],
                         ["bluetooth", "Bluetooth", "bluetooth", "bluetooth devices pair headphones airpods"],
                         ["power", "Power & battery", "battery", "power battery charge profile performance saver"],
                         ["keyboard", "Keyboard", "keyboard", "keyboard layout language repeat shortcuts"],
                         ["pointer", "Mouse & touchpad", "mouse", "mouse touchpad trackpad tap scroll speed"],
                         ["notifications", "Notifications", "bell", "notifications do not disturb banners"],
                         ["accessibility", "Accessibility", "eye", "accessibility text size larger font contrast invert colors reduce motion"],
                         ["apps", "Default apps", "apps", "default apps browser mail open with"],
                         ["storage", "Storage & drives", "drive", "storage disk space usb drives eject trash"],
                         ["about", "About this computer", "info", "about system version nixos hardware"]])
            list.push(sys("settings-" + p[0], p[1] + " settings", p[2], "settings preferences " + p[3], "Open", "Settings", "Settings › " + p[1] + ".",
                          () => { act("Shell.openSettings(" + p[0] + ")", () => Shell.openSettings(p[0]), true); }, "Settings › " + p[1]));
        // Plate actions preview the plate as it will print.
        Object.assign(list.find(a => a.id === "dark"), { "plate": Art.current, "plateMode": "dark" });
        Object.assign(list.find(a => a.id === "light"), { "plate": Art.current, "plateMode": "light" });
        Object.assign(list.find(a => a.id === "appearance"), { "plate": Art.current });
        if (Focus.active)
            list.push(sys("focusEnd", "End focus", "bell", "focus stop end off do not disturb", "End", Focus.clock + " left",
                "Notifications come back now.", () => { act("Focus.stop()", () => Focus.stop()); close(); }, "Focus"));
        const col = Art.collections.find(c => c.id === Theme.selection.collection);
        if (col && col.art.length > 1) {
            const n = ((Theme.selection.art || 0) + 1) % col.art.length;
            list.push(Object.assign(sys("plate", "Next plate", "image", "next plate wallpaper background art picture shuffle", "Print", col.art[n].title,
                "Prints “" + col.art[n].title + "” from " + col.name + ".",
                () => { act("Theming.set(art " + n + ")", () => Theming.set({ "art": n }, "“" + col.art[n].title + "”"), true); close(); }, "azure-folio set --art " + n), { "plate": col.art[n].id }));
        }
        list.push(Network.wifiOn
            ? sys("wifi", "Turn Wi-Fi off", "wifi", "wifi wi-fi wireless network internet radio off", "Turn off", Network.ssid || "On",
                Network.ssid ? "Disconnects from " + Network.ssid + " and turns the radio off." : "Turns the Wi-Fi radio off.",
                () => { act("Network.setWifi(false)", () => Network.setWifi(false)); close(); }, "nmcli radio wifi off")
            : sys("wifi", "Turn Wi-Fi on", "wifi", "wifi wi-fi wireless network internet radio on", "Turn on", "Off",
                "Turns the radio on and joins a known network.",
                () => { act("Network.setWifi(true)", () => Network.setWifi(true)); close(); }, "nmcli radio wifi on"));
        if (Bluetooth.available)
            list.push(Bluetooth.on
                ? sys("bluetooth", "Turn Bluetooth off", "bluetooth", "bluetooth bt radio off headphones", "Turn off", Bluetooth.summary,
                    Bluetooth.connected.length ? "Disconnects " + Bluetooth.summary + " and turns Bluetooth off." : "Turns Bluetooth off.",
                    () => { act("Bluetooth.setOn(false)", () => Bluetooth.setOn(false)); close(); }, "BlueZ · power off")
                : sys("bluetooth", "Turn Bluetooth on", "bluetooth", "bluetooth bt radio on headphones", "Turn on", "Off",
                    "Turns Bluetooth on; paired devices reconnect.",
                    () => { act("Bluetooth.setOn(true)", () => Bluetooth.setOn(true)); close(); }, "BlueZ · power on"));
        return list;
    }
    function suggestions() {
        const want = ["focus25", Theme.dark ? "light" : "dark", "plate"];
        const all = systemActions();
        return want.map(id => all.find(a => a.id === id)).filter(a => a);
    }

    // ---- Emoji: emoji.json (scripts/folio-emoji, from Unicode's emoji-test
    // and CLDR's keywords) beside this file.

    property var emojiList: []
    property var emojiGroups: []
    property bool emojiMissing: false
    function loadEmoji(text) {
        try {
            const d = JSON.parse(text);
            emojiGroups = d.groups || [];
            emojiList = (d.emoji || []).map((x, i) => {
                const lname = String(x[1]).toLowerCase();
                return { "char": x[0], "name": x[1], "lname": lname, "nw": lname.split(/[\s:,]+/).filter(w => w),
                         "kw": x[2] ? String(x[2]).toLowerCase().split(/[|\s]+/) : [], "keywords": x[2] ? String(x[2]).split("|").join(", ") : "",
                         "group": x[3], "order": i };
            });
            emojiMissing = emojiList.length === 0;
        } catch (e) {
            console.warn("Launcher: unreadable emoji.json", e);
            emojiMissing = true;
        }
        if (open && (scope === "emoji" || query.trim())) rebuild(true);
    }
    FileView {
        path: decodeURIComponent(Qt.resolvedUrl("emoji.json").toString().replace(/^file:\/\//, ""))
        printErrors: false
        onLoaded: root.loadEmoji(text())
        onLoadFailed: root.emojiMissing = true
    }
    // Browsing (":" alone): what was copied lately, then each group's first.
    function emojiBrowse() {
        const out = [];
        if (emojiRecent.length)
            out.push({ "title": "Recently copied", "items": emojiRecent.map(c => emojiList.find(e => e.char === c)).filter(e => e).map(e => emojiItem(e, true)) });
        emojiGroups.forEach((g, i) => {
            const list = emojiList.filter(e => e.group === i).slice(0, 24).map(e => emojiItem(e, true));
            if (list.length) out.push({ "title": g, "items": list });
        });
        return out;
    }

    // ---- Files under the home folder: fd (find without it), hidden folders,
    // .gitignored and build output skipped, at most 4 s and a few hundred
    // names per search; a newer query ends the search before it.

    property var fileHits: ({ "query": "", "mode": "", "items": [] })
    property bool fileBusy: false
    property int fileSeq: 0
    function wantFiles(q) {
        if (scope === "files") return true;
        return !scope && q.length >= 3 && !Search.calc(q) && !Search.units(q);
    }
    function scheduleFiles() {
        const q = query.trim().toLowerCase();
        if (!open || !wantFiles(q)) { stopFiles(); return; }
        fileBusy = true;
        findLater.interval = scope === "files" ? 60 : 140;
        findLater.restart();
    }
    function stopFiles() {
        findLater.stop();
        finder.next = null;
        finder.current = null;          // what it prints now is dropped
        if (finder.running) finder.running = false;
        fileBusy = false;
    }
    function findFiles() {
        const q = query.trim().toLowerCase();
        if (!open || !wantFiles(q)) return;
        const mode = scope === "files" && q.length < 2 ? "recent" : "name";
        // The recent files are the same for "" and one letter.
        if (mode === "recent" && fileHits.mode === "recent" && !finder.next) {
            stopFiles();
            rebuild(true);
            return;
        }
        if (fakeFiles) {
            const items = fakeFiles.filter(f => mode === "recent" || Search.fileMatches(f.path, f.name, q));
            fileHits = { "query": q, "mode": mode, "items": items };
            fileBusy = false;
            rebuild(true);
            return;
        }
        const tag = "folio-find " + (++fileSeq);
        const max = mode === "recent" ? 3000 : scope === "files" ? 600 : 300;
        finder.next = { "tag": tag, "query": q, "mode": mode, "command": ["timeout", "4", "sh", "-c", finder.script, "sh",
            tag, mode, Search.filePattern(q), Search.fileGlob(q), home, String(max), q.indexOf("/") >= 0 ? "--full-path" : ""] };
        if (finder.running) {           // ends it (its output is dropped); the next starts when it has
            finder.current = null;
            finder.running = false;
        } else startFinder();
    }
    function startFinder() {
        const n = finder.next;
        if (!n || finder.running) return;
        finder.next = null;
        finder.current = n;
        finder.command = n.command;
        finder.running = true;
    }
    function filesFound(text) {
        const lines = text.split("\n");
        const n = finder.current;
        if (!n || lines[0] !== n.tag) return;           // an ended search
        const items = [];
        const seen = {};
        for (let i = 1; i < lines.length; i++) {
            const f = lines[i].split("\t");
            if (f.length < 4 || !/^\d+$/.test(f[0])) continue;
            const path = f.slice(3).join("\t");
            if (!path.startsWith("/") || seen[path] || path === home) continue;
            seen[path] = true;
            items.push({ "path": path, "name": path.slice(path.lastIndexOf("/") + 1), "dir": f[1] === "directory",
                         "mtime": +f[0], "size": +f[2], "depth": Search.tilde(path, home).split("/").length - 1 });
        }
        fileHits = { "query": n.query, "mode": n.mode, "items": items };
        fileBusy = !!finder.next;
        if (open) rebuild(true);
    }
    // What the last search found that still matches the query, best first.
    function fileResults(q, limit) {
        const h = fileHits;
        const recent = scope === "files" && q.length < 2;
        if (!h.items.length || (h.mode === "recent") !== recent) return [];
        if (recent)     // one letter narrows the recent files
            return h.items.filter(f => !q || Search.fileMatches(f.path, f.name, q)).sort((a, b) => b.mtime - a.mtime).slice(0, limit).map(f => fileItem(f, 0));
        return h.items.filter(f => h.query === q || Search.fileMatches(f.path, f.name, q))
            .map(f => fileItem(f, Search.fileScore(f, q, now)))
            .sort((a, b) => b.score - a.score || b.mtime - a.mtime).slice(0, limit);
    }
    Timer { id: findLater; onTriggered: root.findFiles() }
    Process {
        id: finder
        property var next: null         // the search waiting for this one to end
        property var current: null
        // $1 tag, $2 recent|name, $3 fd pattern, $4 find glob, $5 home, $6 max, $7 --full-path or "".
        // Recent: changed this week, and what GTK apps opened lately.
        readonly property string script: [
            "printf '%s\\n' \"$1\"; set -f",
            "x='-E node_modules -E target -E build -E dist -E __pycache__ -E venv -E site-packages -E vendor -E _build -E bazel-* " +
                "-E *.egg-info -E DerivedData -E steamapps -E go/pkg -E Cache -E cache -E CachedData -E GPUCache -E coverage'",
            "p='( -name .* -o -name node_modules -o -name target -o -name build -o -name dist -o -name __pycache__ -o -name venv -o -name vendor -o -name Cache -o -name cache ) -prune'",
            "{ if [ \"$2\" = recent ]; then",
            "    if command -v fd >/dev/null; then fd -0 -t f --one-file-system --max-depth 9 $x --changed-within 7d . \"$5\";",
            "    else find \"$5\" -xdev -maxdepth 9 $p -o -type f -mtime -7 -print0; fi",
            "    sed -n 's|.*href=\"file://\\([^\"]*\\)\".*|\\1|p' \"${XDG_DATA_HOME:-$5/.local/share}/recently-used.xbel\" 2>/dev/null | tail -n 40 |",
            "      while IFS= read -r u; do printf '%b\\0' \"$(printf '%s' \"$u\" | sed 's/%/\\\\x/g')\"; done",
            "  elif command -v fd >/dev/null; then fd -0 -t f -t d -i --one-file-system --max-depth 9 $x $7 -- \"$3\" \"$5\";",
            "  else find \"$5\" -xdev -maxdepth 9 $p -o \\( -type f -o -type d \\) -iname \"$4\" -print0; fi",
            "} 2>/dev/null | head -z -n \"$6\" | xargs -0r stat --printf '%Y\\t%F\\t%s\\t%n\\n' 2>/dev/null"
        ].join("\n")
        stdout: StdioCollector { onStreamFinished: root.filesFound(text) }
        onRunningChanged: if (!running && next) Qt.callLater(root.startFinder)
    }

    // ---- Ranking: each section ranks its results; sections go by their best
    // match, the calculator first and the web last.

    // keep: results arrived for the same query (files, emoji data); a
    // selection the keyboard moved to stays where it is.
    function rebuild(keep) {
        const raw = query.trim();
        const q = raw.toLowerCase();
        const sections = [];
        let empty = null;
        const was = keep && (sel > 0 || actionsMode) ? current : null;
        if (scope === "files") {
            const recent = q.length < 2;
            const list = fileResults(q, recent ? 40 : 50);
            if (list.length) sections.push({ "title": recent ? "Recent" : "Files", "items": list });
            else if (fileBusy) empty = { "title": recent ? "Looking for recent files…" : "Searching your files…", "subtitle": "In your home folder, without hidden folders or build output.", "glyph": "search" };
            else if (recent) empty = q ? { "title": "No recent file matches “" + raw + "”", "subtitle": "Type another letter to search your home folder.", "glyph": "folder" }
                                       : { "title": "Nothing changed this week", "subtitle": "Type a name to search your home folder.", "glyph": "folder" };
            else empty = { "title": "No files match “" + raw + "”", "subtitle": "Hidden folders and build output are skipped.", "glyph": "folder" };
        } else if (scope === "emoji") {
            if (emojiMissing) empty = { "title": "No emoji list", "subtitle": "scripts/folio-emoji writes it; the Nix package builds it.", "glyph": "sparkle" };
            else if (!q) for (const g of emojiBrowse()) sections.push(g);
            else {
                const list = Search.emoji(emojiList, q, 60).map(x => emojiItem(x.e));
                if (list.length) sections.push({ "title": "Emoji", "items": list });
                else empty = { "title": "No emoji for “" + raw + "”", "subtitle": "Try another word: heart, cat, party, flag.", "glyph": "sparkle" };
            }
        } else if (scope === "clipboard") {
            const list = clips().filter(c => !q || c.text.toLowerCase().indexOf(q) >= 0).slice(0, 50).map(clipItem);
            if (list.length) sections.push({ "title": "Clipboard", "items": list });
            else empty = clips().length
                ? { "title": "Nothing copied matches “" + raw + "”", "subtitle": "Clipboard history keeps the last 50 texts.", "glyph": "note" }
                : { "title": "Nothing copied yet", "subtitle": "Text you copy shows up here, the last 50.", "glyph": "note" };
        } else if (!q) {
            sections.push({ "title": "Frequent", "items": frequent(5).map(e => appItem(e)) });
            sections.push({ "title": "Suggestions", "items": suggestions() });
        } else {
            const c = Search.calc(raw);
            if (c) sections.push({ "title": "Calculator", "top": 1000, "items": [{ "kind": "calc", "calc": c, "title": c.text, "subtitle": c.expression, "mark": "=" }] });
            const why = {};
            const u = c ? null : Search.units(raw, why);
            if (u) sections.push({ "title": "Conversion", "top": 1000, "items": [{ "kind": "unit", "calc": u, "title": u.text, "subtitle": u.expression, "glyph": "arrow" }] });
            const a = appResults(q);
            if (a.length) sections.push({ "title": "Applications", "top": a[0].score, "items": a });
            // On a tie an action beats an app ("dark"); the mode already on sinks.
            const s = systemActions().map(x => { const m = Search.score(x.title, x.words, q); return Object.assign(x, { "score": m ? m + (x.subtitle === "Current" ? -30 : 1) : 0 }); })
                .filter(x => x.score > 0)
                .sort((x, y) => y.score - x.score).slice(0, 6);
            if (s.length) sections.push({ "title": "Actions", "top": s[0].score, "items": s });
            const k = q.length >= 2 ? clips().filter(x => x.text.toLowerCase().indexOf(q) >= 0).slice(0, 3).map(clipItem) : [];
            if (k.length) sections.push({ "title": "Clipboard", "top": 15, "items": k });
            // Files rank under a good app or action match, over a loose one.
            const f = wantFiles(q) ? fileResults(q, 5) : [];
            if (f.length) sections.push({ "title": "Files", "top": Math.min(58, Math.round(f[0].score / 2)), "items": f });
            // Emoji for a plain word, when nothing better matches ("pizza").
            const strong = (a.length && a[0].score >= 60) || (s.length && s[0].score >= 60) || c || u;
            const e = !strong && q.length >= 3 ? Search.emoji(emojiList, q, 4, 45).map(x => emojiItem(x.e)) : [];
            if (e.length) sections.push({ "title": "Emoji", "top": 12, "items": e });
            sections.sort((x, y) => y.top - x.top);
            if (!sections.length && why.clash)
                empty = { "title": why.clash[0].symbol + " and " + why.clash[1].symbol + " don’t convert", "glyph": "arrow",
                          "subtitle": "One measures " + why.clash[0].kind.toLowerCase() + ", the other " + why.clash[1].kind.toLowerCase() + "." };
            else if (!sections.length)
                empty = { "title": "Nothing here matches “" + raw + "”", "subtitle": "Check the spelling, or search the web.", "glyph": "search" };
            sections.push({ "title": "Web", "items": [{ "kind": "web", "query": raw, "glyph": "globe", "title": "Search the web for “" + raw + "”", "subtitle": "DuckDuckGo", "meta": "duckduckgo.com" }] });
        }

        const r = [], it = [];
        let y = 0;
        if (empty) {
            empty.kind = "empty"; empty.h = sections.length ? 176 : 300; empty.y = 0;
            r.push(empty); y += empty.h;
        }
        for (const s of sections) {
            if (!s.items.length) continue;
            const h = r.length ? 36 : 28;
            r.push({ "kind": "header", "title": s.title, "h": h, "y": y });
            y += h;
            for (const x of s.items) {
                x.h = 40; x.y = y; x.index = it.length; x.number = it.length < 9 ? it.length + 1 : 0;
                r.push(x); it.push(x);
                y += 40;
            }
        }
        const key = x => x ? x.kind + "|" + (x.path || x.char || (x.entry && x.entry.id) || x.id || "") + "|" + x.title : "";
        const at = was ? it.findIndex(x => key(x) === key(was)) : -1;
        glide = false;
        if (at < 0) { actionsMode = false; actionIndex = 0; }
        rows = r;
        items = it;
        sel = Math.max(0, at);
        if (at < 0) list.contentY = list.originY - list.topMargin;
        else reveal();
        glide = true;
    }

    function setQuery(t) {
        const p = scope ? null : /^(clip\s|f\s|emoji\s|:)/i.exec(t);
        if (p) {
            scope = { "clip": "clipboard", "f": "files", "emoji": "emoji", ":": "emoji" }[p[1].trim().toLowerCase()];
            field.text = t.slice(p[0].length);         // runs setQuery again
            return;
        }
        query = t;
        rebuild();
        scheduleFiles();
    }

    // ---- Keyboard

    function move(d) {
        if (actionsMode) { actionIndex = Math.max(0, Math.min(actions.length - 1, actionIndex + d)); return; }
        if (!items.length) return;
        sel = Math.max(0, Math.min(items.length - 1, sel + d));
        reveal();
    }
    // Keep the selection in view, with its section's caption when it is first.
    function reveal() {
        const it = current;
        if (!it) return;
        const i = rows.indexOf(it);
        const top = i > 0 && rows[i - 1].kind === "header" ? rows[i - 1].y : it.y;
        const bottom = it.y + it.h;
        if (top - list.topMargin < list.contentY) list.contentY = sel === 0 ? list.originY - list.topMargin : top - list.topMargin;
        else if (bottom + list.bottomMargin > list.contentY + list.height) list.contentY = bottom + list.bottomMargin - list.height;
    }
    function enterActions() {
        if (!current || !actions.length) return;
        actionsMode = true;
        actionIndex = actions.length > 1 ? 1 : 0;
    }
    // Keys the field does not want pass through to it (e.accepted false).
    function key(e) {
        e.accepted = false;
        const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
        ctrlHeld = ctrl || e.key === Qt.Key_Control;
        if (e.key === Qt.Key_Control) return;
        if (ctrl && e.key >= Qt.Key_1 && e.key <= Qt.Key_9) {
            const it = items[e.key - Qt.Key_1];
            if (it) runItem(it, 0);
            e.accepted = true;
            return;
        }
        switch (e.key) {
        case Qt.Key_Escape:
            if (actionsMode) actionsMode = false; else close();
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (current) runItem(current, actionsMode ? actionIndex : 0);
            break;
        case Qt.Key_Up: move(-1); break;
        case Qt.Key_Down: move(1); break;
        case Qt.Key_PageUp: move(-5); break;
        case Qt.Key_PageDown: move(5); break;
        case Qt.Key_Tab:
        case Qt.Key_Backtab:
            if (actionsMode) actionsMode = false; else enterActions();
            break;
        case Qt.Key_Right:
            if (actionsMode || field.cursorPosition < field.text.length) return;
            enterActions();
            break;
        case Qt.Key_Left:
            if (!actionsMode) return;
            actionsMode = false;
            break;
        case Qt.Key_Backspace:
            if (field.text !== "" || !scope) return;
            scope = "";
            rebuild();
            scheduleFiles();
            break;
        default:
            if (ctrl && e.key === Qt.Key_N) { move(1); break; }
            if (ctrl && e.key === Qt.Key_P) { move(-1); break; }
            return;
        }
        e.accepted = true;
    }

    // ---- Opening and closing

    property var targetScreen: Shell.screenFor(Quickshell.screens)

    onOpenChanged: {
        if (!open) { ctrlHeld = false; stopFiles(); return; }
        targetScreen = Shell.screenFor(Quickshell.screens);
        now = Date.now();
        scope = "";
        fileHits = { "query": "", "mode": "", "items": [] };
        if (field.text === Shell.launcherQuery) setQuery(field.text);
        else field.text = Shell.launcherQuery;      // runs setQuery
        field.cursorPosition = field.text.length;
        field.forceActiveFocus();
    }
    // Desktop entries load in the background; results catch up when they do.
    Connections {
        target: Apps
        function onAllChanged() { if (root.open && !root.fakeApps) root.rebuild(); }
    }
    // Clipboard entries arriving while open keep their times fresh.
    Connections {
        target: Clipboard
        function onItemsChanged() { if (root.open && root.scope === "clipboard" && !root.fakeClips) { const keep = root.sel; root.rebuild(); root.sel = Math.min(keep, root.items.length - 1); } }
    }

    PanelWindow {
        id: win
        screen: root.targetScreen
        visible: root.open || frame.opacity > 0.02
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "folio:launcher"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // The frost follows the sheet as it grows and fades.
        readonly property real frost: frame.scale * Math.max(0, Math.min(1, (frame.opacity - 0.1) * 1.6))
        BackgroundEffect.blurRegion: Region {
            x: Math.round(frame.x + frame.width * (1 - win.frost) / 2)
            y: Math.round(frame.y + frame.height * (1 - win.frost) / 2)
            width: Math.round(frame.width * win.frost)
            height: Math.round(frame.height * win.frost)
            radius: Theme.rL * win.frost + nudge.extra
        }
        // Re-sent once the sheet has finished growing (or shrinking).
        BlurNudge { id: nudge; key: win.frost > 0.99 }

        // A light scrim; a click on it closes.
        Rectangle {
            anchors.fill: parent
            color: Theme.rgba(Theme.shade, Theme.dark ? 0.22 : 0.07)
            opacity: frame.opacity
        }
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Item {
            id: frame
            width: 720
            height: 62 + 1 + 400 + 1 + 38
            x: Math.round((parent.width - width) / 2)
            y: Math.round(Math.max(24, (parent.height - height) * 0.4))
            opacity: root.open ? 1 : 0
            scale: root.open ? 1 : 0.965
            // Opacity settles in about 150 ms, so reopening feels instant.
            // "Still" motion cuts instead.
            Behavior on opacity { enabled: Theme.motion > 0.05; SpringAnimation { spring: 12; damping: 0.75; epsilon: 0.004 } }
            Behavior on scale { enabled: Theme.motion > 0.05; SpringPanel { epsilon: 0.0005 } }

            MouseArea { anchors.fill: parent }

            Sheet {
                anchors.fill: parent
                radius: Theme.rL
                color: Theme.sheetStrong
                elevation: 1.4
            }

            Item {
                anchors.fill: parent

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // The field: everything typed lands here.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: 62
                        Layout.leftMargin: 22
                        Layout.rightMargin: 20
                        spacing: 12

                        Icon { name: "search"; size: 20; color: Theme.ink }
                        Rectangle {
                            visible: root.scope !== ""
                            implicitWidth: chip.implicitWidth + 20
                            implicitHeight: 26
                            radius: 8
                            color: Theme.ink
                            Label { id: chip; anchors.centerIn: parent; text: root.scopes[root.scope] ? root.scopes[root.scope].title : ""; color: Theme.paper; font.pixelSize: Theme.fsS; font.weight: Font.Medium }
                        }
                        TextInput {
                            id: field
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.fillHeight: true
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            color: Theme.text
                            selectionColor: Theme.rgba(Theme.ink, 0.24)
                            selectedTextColor: Theme.text
                            font.family: Theme.ui
                            font.pixelSize: Theme.fsXl
                            maximumLength: 400
                            focus: true
                            onTextChanged: root.setQuery(text)
                            Keys.onPressed: e => root.key(e)
                            Keys.onReleased: e => { if (e.key === Qt.Key_Control) root.ctrlHeld = false; }
                            cursorDelegate: Rectangle {
                                width: 2
                                radius: 1
                                color: Theme.ink
                                visible: field.activeFocus
                                SequentialAnimation on opacity {
                                    running: field.activeFocus && root.open
                                    loops: Animation.Infinite
                                    PropertyAction { value: 1 }
                                    PauseAnimation { duration: 560 }
                                    PropertyAction { value: 0 }
                                    PauseAnimation { duration: 420 }
                                }
                            }
                            // A long query scrolls in under a fade, not a hard cut.
                            Rectangle {
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                width: 22
                                // (cursorRectangle moves when the text scrolls, so this re-evaluates)
                                visible: field.contentWidth > field.width && field.cursorRectangle.x > -1 && field.positionToRectangle(0).x < -1
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: Theme.sheetStrong }
                                    GradientStop { position: 1; color: Theme.rgba(Theme.sheetBase, 0) }
                                }
                            }
                            Label {
                                anchors.fill: parent
                                visible: field.text === ""
                                text: root.scopes[root.scope] ? root.scopes[root.scope].hint : "Search apps, files, actions, emoji…"
                                color: Theme.text3
                                font.pixelSize: Theme.fsXl
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.rule }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 0

                        ListView {
                            id: list
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: root.rows.length
                            topMargin: 6
                            bottomMargin: 8
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight + topMargin + bottomMargin > height

                            Rectangle {
                                parent: list.contentItem
                                z: -1
                                visible: root.current !== null
                                x: 8
                                width: list.width - 16
                                height: 40
                                y: root.current ? root.current.y : 0
                                radius: Theme.inner(Theme.rL, 8)
                                color: root.actionsMode ? Theme.wellStrong : Theme.ink
                                Behavior on y { enabled: root.glide && Theme.motion > 0.05; SpringPress {} }
                                Behavior on color { ColorAnimation { duration: Theme.tQuick } }
                            }

                            // An index model: the rows stay the same objects (a JS array
                            // model would copy them).
                            delegate: ResultRow {
                                required property int index
                                width: ListView.view.width
                                item: root.rows[index] || ({})
                                selected: item.index !== undefined && item.index === root.sel
                                inked: selected && !root.actionsMode
                                showNumber: root.ctrlHeld
                                onHovered: at => {
                                    if (at.x === root.pointer.x && at.y === root.pointer.y) return;
                                    root.pointer = at;
                                    if (item.index !== undefined && !root.actionsMode) { root.glide = true; root.sel = item.index; }
                                }
                                onActivated: if (item.index !== undefined) { root.sel = item.index; root.runItem(root.items[item.index], 0); }
                            }
                        }

                        Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: Theme.rule }

                        Preview {
                            Layout.preferredWidth: 300
                            Layout.fillHeight: true
                            item: root.current
                            actions: root.actions
                            active: root.actionsMode ? root.actionIndex : 0
                            focused: root.actionsMode
                            now: root.now
                            awake: win.visible
                            onRun: index => root.runItem(root.current, index)
                            Rectangle { anchors.fill: parent; z: -1; color: Theme.rgba(Theme.tint, 0.035) }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.rule }

                    // What the keys do, here and now.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: 38
                        Layout.leftMargin: 20
                        Layout.rightMargin: 14
                        spacing: 6

                        // Before typing: the prefixes that narrow the search.
                        Repeater {
                            model: !root.query.trim() && !root.scope && !root.actionsMode ? [["clip", "Clipboard"], ["f", "Files"], [":", "Emoji"]] : []
                            RowLayout {
                                required property var modelData
                                required property int index
                                spacing: 4
                                Layout.leftMargin: index ? 10 : 0
                                KeyCap { text: modelData[0] }
                                KeyCap { visible: modelData[0] !== ":"; text: "Space" }
                                Label { text: modelData[1]; font.pixelSize: Theme.fsS; color: Theme.text2; Layout.leftMargin: 2 }
                            }
                        }
                        Cap {
                            visible: root.query.trim() || root.scope || root.actionsMode
                            text: {
                                if (root.actionsMode && root.current) return root.current.title;
                                const n = root.items.filter(x => x.kind !== "web").length;
                                if (root.scope === "clipboard") return n + (n === 1 ? " entry" : " entries");
                                if (root.scope === "files") return n === 0 && root.fileBusy ? "Searching…" : n + (n === 1 ? " file" : " files");
                                if (root.scope === "emoji") return n + " emoji";
                                return n === 0 ? "No results" : n + (n === 1 ? " result" : " results");
                            }
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                        }
                        Item { visible: !root.query.trim() && !root.scope && !root.actionsMode; Layout.fillWidth: true }
                        Repeater {
                            model: root.ctrlHeld ? [["Ctrl", "1–9", "Run that result"]]
                                 : root.actionsMode ? [["↵", "", "Run"], ["↑↓", "", "Choose"], ["Esc", "", "Back"]]
                                 : root.current ? [["↵", "", root.verb(root.current)], ["Tab", "", "Actions"], ["Esc", "", "Close"]]
                                 : [["Esc", "", "Close"]]
                            RowLayout {
                                required property var modelData
                                spacing: 4
                                Layout.leftMargin: 8
                                KeyCap { text: modelData[0] }
                                KeyCap { visible: modelData[1] !== ""; text: modelData[1] }
                                Label { text: modelData[2]; font.pixelSize: Theme.fsS; color: Theme.text2; Layout.leftMargin: 2 }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Fixtures: normal, stress (fake apps and clipboard), empty (nothing
    // found), long (a 200-character query), calc, clip, clip-empty, files,
    // files-stress, files-empty (fake files), emoji, emoji-browse,
    // emoji-stress, emoji-empty, units, units-stress, units-empty.

    function fixture(name) {
        fakeApps = null;
        fakeClips = null;
        fakeFiles = null;
        if (name === "files") {
            fakeFiles = sampleFiles();
            Shell.openLauncher("f ");
        } else if (name === "files-search") {
            fakeFiles = sampleFiles();
            Shell.openLauncher("report");
        } else if (name === "files-stress") {
            fakeFiles = stressFiles();
            Shell.openLauncher("f report");
        } else if (name === "files-empty") {
            fakeFiles = [];
            Shell.openLauncher("f qzxvjwk");
        } else if (name === "emoji") {
            Shell.openLauncher(":heart");
        } else if (name === "emoji-browse") {
            Shell.openLauncher(":");
        } else if (name === "emoji-stress") {
            Shell.openLauncher(":person");
        } else if (name === "emoji-empty") {
            Shell.openLauncher(":qzxvjwk");
        } else if (name === "units") {
            Shell.openLauncher("5 km in mi");
        } else if (name === "units-stress") {
            Shell.openLauncher("123456789.123456789 GiB in bits");
        } else if (name === "units-empty") {
            Shell.openLauncher("5 km in kg");
        } else if (name === "stress") {
            fakeApps = stressApps();
            fakeClips = stressClips();
            Shell.openLauncher("a");
        } else if (name === "long") {
            Shell.openLauncher("the quick brown fox jumps over the lazy dog while a printer in Campana sets one more line of type in azure ink on cream paper, then another, and another, and another, until the whole sheet is full of it");
        } else if (name === "clip") {
            fakeClips = stressClips();
            Shell.openLauncher("clip ");
        } else if (name === "clip-empty") {
            fakeClips = [];
            Shell.openLauncher("clip ");
        } else if (name === "calc") {
            Shell.openLauncher("(1200 + 345.5) × 1.21");
        } else if (name === "empty") {
            Shell.openLauncher("qzxvjwk");
        } else if (name === "normal") {
            Shell.openLauncher("");
        }
    }
    function stressApps() {
        const icons = ["org.gnome.Nautilus", "com.mitchellh.ghostty", "firefox", "gimp", "", "no-such-icon-anywhere", "code", "org.gnome.Settings"];
        const words = ["Atlas", "Aurora", "Archive", "Ambient", "Anchor", "Arcade", "Aperture", "Almanac"];
        const out = [];
        for (let i = 0; i < 40; i++) {
            const name = (words[i % words.length] + " Professional Photo Library Manager and RAW Developer Suite " + i).slice(0, 60);
            out.push({
                "fake": true, "id": "fake.app" + i, "name": name,
                "genericName": "Photo Library Manager, RAW Developer, Batch Exporter and Print Studio",
                "comment": "Organise a lifetime of photographs, develop RAW files with film-accurate profiles, export in batches and print contact sheets on any paper size, with or without colour management.",
                "icon": icons[i % icons.length], "keywords": ["photo"],
                "actions": i % 3 === 0 ? ["New Window in a Separate Profile With Extensions Disabled", "Import From Camera, Card Reader or Phone", "Open the Most Recent Library", "Export Everything Selected as Full-Resolution JPEG", "Print a Contact Sheet", "Safe Mode"].map(n => ({ "name": n, "icon": "", "execute": () => {} })) : []
            });
        }
        return out;
    }
    // Fake files; the README, this launcher's source and the current plate are
    // real, so the text and image previews have something to show.
    function fakeFile(path, hoursAgo, size, dir) {
        return { "path": path, "name": path.slice(path.lastIndexOf("/") + 1), "dir": !!dir, "size": size || 0,
                 "mtime": Math.round(Date.now() / 1000 - hoursAgo * 3600), "depth": Search.tilde(path, home).split("/").length - 1 };
    }
    function sampleFiles() {
        const shellDir = decodeURIComponent(Qt.resolvedUrl("../..").toString().replace(/^file:\/\//, "")).replace(/\/$/, "");
        const h = home;
        return [
            fakeFile(h + "/Documents/Work/Quarterly report Q3 2026.pdf", 5, 2400000),
            fakeFile(Art.share + "art/" + Art.current + "/azure-light-desktop.png", 30, 5100000),
            fakeFile(shellDir + "/README.md", 2, 7400),
            fakeFile(shellDir + "/Modules/Launcher/Search.js", 1, 24000),
            fakeFile(h + "/Documents/Notes", 3, 0, true),
            fakeFile(h + "/Documents/Budget 2027.ods", 50, 81000),
            fakeFile(h + "/Downloads/Invoice 0142, Estudio Campana.pdf", 80, 310000),
            fakeFile(h + "/Pictures/Patagonia 2026", 200, 0, true),
            fakeFile(h + "/Music/Mate a las cinco.flac", 900, 38000000),
            fakeFile(h + "/Documents/Reports", 2000, 0, true),
            fakeFile(h + "/Downloads/report-template.docx", 4000, 52000),
            fakeFile(h + "/Videos/Report from Campana.mp4", 9000, 812000000)
        ];
    }
    function stressFiles() {
        const out = [];
        const deep = home + "/Documents/Work/Clients/Estudio Campana de Tipografía y Grabado/2026/Quarterly reports/Drafts and archived versions";
        const exts = ["pdf", "docx", "ods", "png", "md", "zip", "mp4", "txt"];
        for (let i = 0; i < 60; i++)
            out.push(fakeFile(deep + (i % 3 ? "/Subfolder " + i : "") + "/Quarterly financial report for the Campana print studio with scanned receipts, final v" + i + "." + exts[i % exts.length],
                              i * 7, 1000 * Math.pow(3, i % 14), i % 9 === 0));
        return out;
    }
    function stressClips() {
        const t = Date.now();
        const base = [
            "https://www.example.org/a/very/long/path/that/keeps/going/and/going/until/it/no/longer/fits/anywhere?utm_source=folio&utm_medium=launcher&utm_campaign=stress-test-with-a-very-long-query-string",
            "nix build path:.#nixosConfigurations.bonhart.config.system.build.toplevel --print-build-logs",
            "function rebuild() {\n    const raw = query.trim();\n    const q = raw.toLowerCase();\n    const sections = [];\n    for (const s of sections)\n        if (!s.items.length) continue;\n}\n",
            "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
            "¿Mate a las cinco? Llevo facturas.",
            "{\"collection\": \"ronin\", \"mode\": \"light\", \"ink\": \"slate\", \"art\": 0, \"randomLogin\": true}",
            "mariano.miguel@example.com",
            "#214c94",
            "Supercalifragilisticexpialidocious-without-any-spaces-at-all-so-it-has-to-break-somewhere-in-the-middle-of-the-word-or-it-overflows"
        ];
        const out = [];
        for (let i = 0; i < 24; i++)
            out.push({ "text": i < base.length ? base[i] : "Clipboard entry number " + i + " · " + base[i % base.length].slice(0, 40), "time": t - i * 7 * 60000 });
        return out;
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { Shell.toggleLauncher(); }
        function open(query: string): void { Shell.openLauncher(query); }
        function close(): void { Shell.launcherOpen = false; }
        function fixture(name: string): void { root.fixture(name); }
        // What the last action ran, or in the harness, would have run.
        function last(): string { return root.lastRun; }
        // For tests: what the launcher shows and where the keyboard is.
        function state(): string {
            return JSON.stringify({ "open": root.open, "query": root.query, "scope": root.scope, "selected": root.current ? root.current.title : null,
                                    "index": root.sel, "results": root.items.length, "actionsMode": root.actionsMode, "action": root.actionsMode ? root.actions[root.actionIndex].label : null,
                                    "kind": root.current ? root.current.kind : null, "filesBusy": root.fileBusy, "files": root.fileHits.items.length, "emoji": root.emojiList.length,
                                    "focus": field.activeFocus, "windowActive": win.active === true });
        }
    }
}
