import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

// The dock: a sheet floating at the bottom centre of every screen. Pinned
// apps (Settings "dock.pinned"), then running apps that are not pinned (niri
// windows grouped by app_id), a rule, then Settings. It never moves for other
// panels. This file owns the app list; DockWindow draws it on each screen.
Scope {
    id: root

    // Test data (fixture normal | stress | empty); null shows the live system.
    // Fixture actions are dry: nothing launches, focuses or saves.
    property var fx: null
    // Icon mode preview for this session (ipc dock icons), "" = the setting.
    property string iconsPreview: ""
    readonly property string iconMode: iconsPreview || Settings.get("dock.icons") || "original"
    readonly property bool magnify: Settings.get("dock.magnify") !== false

    // icon source -> "square" (ships its own tile) or "free" (round, free-form).
    property var shapes: ({})
    function setShape(src, shape) { const s = Object.assign({}, shapes); s[src] = shape; shapes = s; }

    // Entries and windows per item key, beside the model (it holds plain values).
    property var entries: ({})
    property var windowIds: ({})

    // [id, name override, windows, pinned]; ids resolve to real desktop entries.
    readonly property var fixtures: ({
        "normal": [["org.gnome.Nautilus", "", 0, true], ["google-chrome", "", 1, true], ["com.mitchellh.ghostty", "", 2, true],
                   ["spotify", "", 0, true], ["code", "", 0, true], ["slack", "", 1, false]],
        "stress": [["org.gnome.Nautilus", "", 1, true], ["google-chrome", "", 3, true], ["com.mitchellh.ghostty", "", 2, true],
                   ["spotify", "", 0, true], ["code", "Visual Studio Code — Insiders (Workspace) · Restricted Mode · 3 problems in folio.js", 1, true],
                   ["obsidian", "", 0, true], ["firefox", "", 0, true], ["gimp", "GNU Image Manipulation Program 3.0 — Untitled-1 [Imported]", 0, true],
                   ["org.gnome.Calendar", "", 0, true], ["dev.zed.Zed", "", 0, true], ["kitty", "", 0, true], ["davinci-resolve", "", 0, true],
                   ["onlyoffice-desktopeditors", "", 0, true], ["org.darktable.darktable", "", 0, true],
                   ["slack", "", 4, false], ["com.obsproject.Studio", "", 1, false], ["OrcaSlicer", "", 1, false],
                   ["net.example.NoIconAtAll", "Payments Reconciliation Console (staging, eu-west-1)", 1, false]],
        "empty": []
    })

    IpcHandler {
        target: "dock"
        // normal | stress | empty; anything else (live) returns to real data.
        function fixture(name: string): void {
            const f = root.fixtures[name];
            root.fx = f ? f.map(a => ({ "id": a[0], "name": a[1], "windows": a[2], "pinned": a[3] })) : null;
        }
        // Preview an icon mode for this session (original | plated | printed);
        // anything else returns to the saved setting.
        function icons(mode: string): void { root.iconsPreview = ["original", "plated", "printed"].indexOf(mode) >= 0 ? mode : ""; }
        // Press the nth item (0-based; the last is Settings) on the focused
        // screen: click | middle | menu. Use with a fixture to keep it dry.
        function press(index: int, how: string): void { root.pressed(index, how || "click"); }
        // Close an open menu.
        function close(): void { root.pressed(-1, "close"); }
    }
    signal pressed(int index, string how)

    // ------------------------------------------------------------ the list

    function lookup(id) {
        if (!id) return null;
        return DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id) || null;
    }
    function iconFor(entry, id) {
        const name = entry && entry.icon ? entry.icon : "";
        if (name.startsWith("/")) return "file://" + name;
        return (name && Quickshell.iconPath(name, true)) || Quickshell.iconPath(id, true) || Quickshell.iconPath(id.toLowerCase(), true) || "";
    }
    function prettify(id) {
        const tail = id.split(".").pop() || id;
        return tail.charAt(0).toUpperCase() + tail.slice(1);
    }
    function matches(appId, id, entry) {
        const a = appId.toLowerCase();
        if (a === id.toLowerCase()) return true;
        if (!entry) return false;
        if (entry.id.toLowerCase() === a || (entry.startupClass || "").toLowerCase() === a) return true;
        const h = DesktopEntries.heuristicLookup(appId);
        return !!h && h.id === entry.id;
    }
    function item(key, id, entry, name, ids, pinned) {
        return { "key": key, "id": id, "entry": entry, "name": name || (entry && entry.name) || prettify(id),
                 "icon": iconFor(entry, id), "pinned": pinned, "running": ids.length, "ids": ids };
    }

    function live() {
        DesktopEntries.applications.values;          // re-run once entries load
        const pinned = Settings.get("dock.pinned") || [];
        const groups = {};
        for (const w of Object.values(Niri.windows).sort((a, b) => a.id - b.id)) {
            const k = w.app_id || "unknown";
            (groups[k] = groups[k] || []).push(w.id);
        }
        const used = {}, out = [], seen = {};
        for (const id of pinned) {
            const e = lookup(id);
            const key = e ? e.id : id;
            if (seen[key]) continue;
            seen[key] = true;
            let ids = [];
            for (const appId in groups)
                if (!used[appId] && matches(appId, id, e)) { used[appId] = true; ids = ids.concat(groups[appId]); }
            out.push(item(key, id, e, "", ids, true));
        }
        for (const appId in groups) {
            if (used[appId]) continue;
            const e = lookup(appId);
            const key = e ? e.id : appId;
            const prev = out.find(x => x.key === key);
            if (prev) { prev.ids = prev.ids.concat(groups[appId]); prev.running = prev.ids.length; continue; }
            out.push(item(key, appId, e, "", groups[appId], false));
        }
        return out;
    }
    function fixtureItems() {
        DesktopEntries.applications.values;
        const list = fx.filter(a => a.pinned).concat(fx.filter(a => !a.pinned));
        return list.map((a, i) => {
            const e = lookup(a.id);
            return item(e ? e.id : a.id, a.id, e, a.name, Array.from({ length: a.windows }, (_, j) => -(i * 10 + j + 1)), a.pinned);
        });
    }
    readonly property var target: fx ? fixtureItems() : live()
    // Bursts (entries loading, a window retitling) settle into one sync.
    onTargetChanged: Qt.callLater(resync)
    function resync() { sync(target); }

    // A stable model: delegates keep their state (magnification, bounce)
    // while windows come and go; removed apps shrink away before they leave.
    ListModel { id: model }
    readonly property alias model: model
    property bool ready: false
    Timer { interval: 600; running: true; onTriggered: root.ready = true }

    function sync(list) {
        const e = {}, w = {};
        for (const it of list) { e[it.key] = it.entry; w[it.key] = it.ids; }
        entries = Object.assign({}, entries, e);
        windowIds = w;
        const keys = list.map(x => x.key);
        for (let i = 0; i < model.count; i++)
            if (keys.indexOf(model.get(i).key) < 0 && !model.get(i).leaving) model.setProperty(i, "leaving", true);
        let pos = 0;
        for (const it of list) {
            while (pos < model.count && model.get(pos).leaving && model.get(pos).key !== it.key) pos++;
            let found = -1;
            for (let k = pos; k < model.count; k++) if (model.get(k).key === it.key) { found = k; break; }
            const row = { "key": it.key, "appId": it.id, "name": it.name, "icon": it.icon, "pinned": it.pinned, "running": it.running, "leaving": false, "fresh": root.ready };
            if (found < 0) {
                model.insert(pos, row);
            } else {
                if (found !== pos) model.move(found, pos, 1);
                for (const r of ["appId", "name", "icon", "pinned", "running", "leaving"])
                    if (model.get(pos)[r] !== row[r]) model.setProperty(pos, r, row[r]);
            }
            pos++;
        }
    }
    function removeKey(key) {
        for (let i = 0; i < model.count; i++)
            if (model.get(i).key === key && model.get(i).leaving) { model.remove(i); return; }
    }

    // ------------------------------------------------------------ actions

    function stamp(t) { return t ? t.secs + t.nanos / 1e9 : 0; }
    // Focus the app's most recent window; when it already has focus, the next.
    function focus(key) {
        const ws = (windowIds[key] || []).map(id => Niri.windows[id]).filter(Boolean);
        if (!ws.length) return false;
        ws.sort((a, b) => stamp(b.focus_timestamp) - stamp(a.focus_timestamp));
        const i = ws.findIndex(x => x.is_focused);
        Niri.focusWindow(ws[i === 0 && ws.length > 1 ? 1 : 0].id);
        return true;
    }
    function launch(key, action) {
        if (fx) { setFixture(key, { "windows": fxEntry(key).windows + 1 }); return true; }
        const e = entries[key];
        if (!e) return false;
        Apps.launch(e, action || null);
        return true;
    }
    function newWindow(key) {
        const e = entries[key];
        const a = e ? (e.actions || []).find(x => /new.?window/i.test(x.id) || /new window/i.test(x.name)) : null;
        return launch(key, a);
    }
    function activate(key) {
        if (fx) return fxEntry(key).windows > 0 ? "focus" : (launch(key) ? "launch" : "");
        if (focus(key)) return "focus";
        return launch(key) ? "launch" : "";
    }
    function closeAll(key) {
        if (fx) { setFixture(key, { "windows": 0 }); return; }
        for (const id of windowIds[key] || []) Niri.closeWindow(id);
    }
    function setPinned(key, appId, pin) {
        if (fx) { setFixture(key, { "pinned": pin }); return; }
        const list = (Settings.get("dock.pinned") || []).slice();
        const e = entries[key];
        const ids = [key, appId].concat(e ? [e.id] : []);
        const kept = list.filter(id => ids.indexOf(id) < 0 && (lookup(id) || {}).id !== key);
        Settings.set("dock.pinned", pin ? kept.concat([e ? e.id : appId]) : kept);
    }
    function fxEntry(key) { return fx.find(a => { const e = lookup(a.id); return (e ? e.id : a.id) === key; }) || { "windows": 0 }; }
    function setFixture(key, change) {
        fx = fx.map(a => { const e = lookup(a.id); return (e ? e.id : a.id) === key ? Object.assign({}, a, change) : a; });
    }

    Variants {
        model: Quickshell.screens
        DockWindow {
            required property var modelData
            screen: modelData
            dock: root
        }
    }
}
