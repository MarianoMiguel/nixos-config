pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Displays: what niri has connected, and the layouts Folio remembers for each
// set of connected displays (~/.config/folio/displays.json, seeded once from
// DMS's profiles). Applying a layout writes ~/.config/niri/folio-outputs.kdl,
// which niri includes while Folio is the shell (mariano-shell points
// shell-outputs.kdl at it) and reloads at once. When the set of connected
// displays changes, its most recent layout comes back; a set never seen
// before gets every display on, placed by niri. A layout never turns every
// display off.
//
// Outputs are keyed as niri names them in its config: "make model serial".
// In the harness, a fixture stands in for niri and every file stays in the
// harness's runtime directory.
Singleton {
    id: root

    readonly property bool harness: !!Quickshell.env("FOLIO_HARNESS")
    readonly property string home: Quickshell.env("HOME")
    readonly property string runDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/folio-displays"
    readonly property string layoutsPath: harness ? runDir + "/displays.json" : home + "/.config/folio/displays.json"
    readonly property string kdlPath: harness ? runDir + "/outputs.kdl" : home + "/.config/niri/folio-outputs.kdl"
    readonly property string dmsProfiles: home + "/.config/DankMaterialShell/monitors.json"

    // ---------------------------------------------------------------- state

    property string fixture: ""
    readonly property bool available: fixture !== "" || Niri.available
    property var outputs: []            // normalized, sorted: built-in first, then left to right
    property var layouts: []            // [{id, name, used, outputs: {key: cfg}}]
    property bool auto: true
    property string activeId: ""
    property bool loaded: false         // displays.json read (or found missing)
    property bool identifying: false
    property string lastError: ""

    readonly property string setKey: outputs.map(o => o.key).sort().join("\n")
    readonly property var current: layoutsFor(setKey)
    readonly property var active: layouts.find(l => l.id === activeId && setOf(l) === setKey) || null
    readonly property var others: layouts.filter(l => setOf(l) !== setKey)
    readonly property int onCount: outputs.filter(o => o.on).length

    // A layout came back by itself (displays changed) or by cycle(); "" for a
    // set of displays never seen before.
    signal applied(string name)

    // Clamshell: with the lid closed and another display on, the built-in
    // panel goes off without changing any saved layout, and comes back when
    // the lid opens. niri's lid switch events call `displays lid` (Folio's
    // binds); the state at start is read from ACPI.
    property bool lidClosed: false
    readonly property bool clamshell: Settings.get("displays.clamshell") !== false
    readonly property bool clamped: lidClosed && clamshell && outputs.some(o => !o.builtin && o.on)
    function setLid(closed) { if (lidClosed !== closed) { lidClosed = closed; rewrite(); } }
    onClamshellChanged: rewrite()
    Process {
        running: !root.harness
        command: ["sh", "-c", "cat /proc/acpi/button/lid/*/state 2>/dev/null | head -1"]
        stdout: StdioCollector { onStreamFinished: root.lidClosed = /closed/.test(text) }
    }

    // ---------------------------------------------------------------- reading

    // niri's transforms ("Normal", "_90", "Flipped270") to its config words.
    function kdlTransform(t) {
        const m = { "Normal": "normal", "_90": "90", "_180": "180", "_270": "270", "Flipped": "flipped", "Flipped90": "flipped-90", "Flipped180": "flipped-180", "Flipped270": "flipped-270" };
        if (m[t]) return m[t];
        const s = String(t || "normal").toLowerCase().replace(/^_/, "");
        return Object.values(m).indexOf(s) >= 0 ? s : "normal";
    }
    function rotated(transform) { return /90|270/.test(transform); }
    function modeId(m) { return m.width + "x" + m.height + "@" + (m.refresh_rate / 1000).toFixed(3); }
    function parseMode(id) {
        const r = /^(\d+)x(\d+)(?:@([\d.]+))?$/.exec(id || "");
        return r ? { "w": +r[1], "h": +r[2], "hz": r[3] ? +r[3] : 0 } : null;
    }
    function keyOf(o) { return (o.make || "Unknown") + " " + (o.model || "Unknown") + " " + (o.serial || "Unknown"); }
    function builtin(name) { return /^(eDP|LVDS|DSI)/.test(name || ""); }

    function normalize(raw) {
        const list = Object.values(raw).map(o => {
            const modes = (o.modes || []).map(m => ({ "id": modeId(m), "w": m.width, "h": m.height, "hz": m.refresh_rate / 1000, "preferred": !!m.is_preferred }));
            const cur = o.current_mode !== null && o.current_mode !== undefined ? modes[o.current_mode] : null;
            const pref = modes.find(m => m.preferred) || modes[0] || null;
            const lg = o.logical || {};
            const mm = o.physical_size || [0, 0];
            const label = builtin(o.name) ? "Built-in display" : ((o.model || "").trim() || (o.make || "").trim() || o.name);
            return {
                "key": keyOf(o), "name": o.name, "make": (o.make || "").trim(), "model": (o.model || "").trim(), "label": label,
                "builtin": builtin(o.name), "modes": modes, "on": !!cur, "mode": (cur || pref || { "id": "" }).id,
                "preferredMode": pref ? pref.id : "",
                "x": lg.x || 0, "y": lg.y || 0, "scale": lg.scale || 1, "transform": kdlTransform(lg.transform),
                "w": lg.width || (cur ? cur.w : 0), "h": lg.height || (cur ? cur.h : 0),
                "vrr": !!o.vrr_enabled, "vrrSupported": !!o.vrr_supported,
                "mm": mm, "inches": mm[0] > 0 ? Math.sqrt(mm[0] * mm[0] + mm[1] * mm[1]) / 25.4 : 0
            };
        });
        list.sort((a, b) => (b.builtin - a.builtin) || (b.on - a.on) || (a.x - b.x) || (a.y - b.y) || a.name.localeCompare(b.name));
        return list;
    }

    function refresh() {
        if (fixture !== "") { outputs = normalize(fixtureRaw); return; }
        if (Niri.available) probe.running = true;
    }
    property bool refreshAgain: false
    Process {
        id: probe
        command: ["niri", "msg", "--json", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.outputs = root.normalize(JSON.parse(text)); } catch (e) { console.warn("Outputs: unreadable niri outputs", e); }
            }
        }
        onRunningChanged: if (!running && root.refreshAgain) { root.refreshAgain = false; running = true; }
    }
    Timer { id: refreshSoon; interval: 350; onTriggered: { if (probe.running) root.refreshAgain = true; else root.refresh(); } }
    // With every display off there is no window and timers may not tick: act at once.
    function refreshLater() { if (Quickshell.screens.length === 0) refresh(); else refreshSoon.restart(); }

    // Hotplug: DRM change events (a display that is off has no screen, so
    // Quickshell's screen list alone can miss it), screens, and niri reloads.
    Process {
        running: !root.harness && Niri.available
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=drm"]
        stdout: SplitParser { onRead: line => { if (/change|add|remove/.test(line)) root.refreshLater(); } }
    }
    Connections { target: Quickshell; function onScreensChanged() { root.refreshLater(); } }
    Connections {
        target: Niri
        function onConfigLoaded(failed) {
            if (failed && root.wrote) {
                root.lastError = "niri could not read the display layout";
                console.warn("Outputs:", root.lastError);
            }
            root.refreshLater();
        }
    }

    // ---------------------------------------------------------------- layouts

    function setOf(l) { return Object.keys(l.outputs || {}).sort().join("\n"); }
    function layoutsFor(set) { return layouts.filter(l => setOf(l) === set).sort((a, b) => (b.used || 0) - (a.used || 0)); }
    function outputFor(key) { return outputs.find(o => o.key === key) || null; }

    // The live state as a layout's outputs.
    function snapshot() {
        const c = {};
        for (const o of outputs) c[o.key] = { "mode": o.mode, "x": o.x, "y": o.y, "scale": o.scale, "transform": o.transform, "vrr": o.vrr, "off": !o.on };
        return c;
    }
    // What a layout would be, with any missing piece taken from the live state.
    function complete(cfg) {
        const s = snapshot(), c = {};
        for (const k in s) c[k] = Object.assign({}, s[k], cfg[k] || {});
        return c;
    }
    function same(a, b) {
        const ka = Object.keys(a).sort(), kb = Object.keys(b).sort();
        if (ka.join("\n") !== kb.join("\n")) return false;
        for (const k of ka) {
            const x = a[k], y = b[k];
            if (!!x.off !== !!y.off) return false;
            if (x.off) continue;
            if (x.mode !== y.mode || Math.abs(x.scale - y.scale) > 0.001 || x.transform !== y.transform || !!x.vrr !== !!y.vrr) return false;
            if (x.x !== null && y.x !== null && (x.x !== y.x || x.y !== y.y)) return false;
        }
        return true;
    }
    // A short description: "3 displays · Built-in off".
    function summary(l) {
        const keys = Object.keys(l.outputs);
        const off = keys.filter(k => l.outputs[k].off).map(k => labelFor(k));
        const n = keys.length - off.length;
        return (n === 1 ? "1 display" : n + " displays") + (off.length ? " · " + off.join(", ") + " off" : "");
    }
    // Names of displays seen before, so layouts for displays not connected
    // now still read "LC34G55T", not a serial number.
    property var names: ({})
    onOutputsChanged: {
        if (!loaded) return;
        let changed = false;
        const n = Object.assign({}, names);
        for (const o of outputs) if (n[o.key] !== o.label) { n[o.key] = o.label; changed = true; }
        if (changed) { names = n; save(); }
    }
    function labelFor(key) {
        const o = outputFor(key);
        if (o) return o.label;
        if (names[key]) return names[key];
        // "make model serial": drop the serial and a PNP(...) maker; a long
        // maker ("Samsung Electric Company") leaves the model alone.
        const t = key.split(" ").filter(x => x).slice(0, -1).filter(x => !/^PNP\(/.test(x));
        return t.length > 2 ? t[t.length - 1] : t.join(" ") || key;
    }
    function displayNames(l) { return Object.keys(l.outputs).map(labelFor).join(", "); }

    function autoName(cfg) {
        const keys = Object.keys(cfg);
        const on = keys.filter(k => !cfg[k].off);
        if (keys.length === 1) return outputFor(keys[0]) && outputFor(keys[0]).builtin ? "Laptop only" : labelFor(keys[0]);
        const ext = on.filter(k => !(outputFor(k) || {}).builtin);
        const base = on.length < keys.length && ext.length === on.length ? "Docked" : (on.length === 1 ? labelFor(on[0]) + " only" : "Extended");
        let name = base, n = 2;
        while (current.some(l => l.name === name)) name = base + " " + n++;
        return name;
    }

    function save() {
        layoutsFile.setText(JSON.stringify({ "version": 1, "auto": auto, "names": names, "layouts": layouts }, null, 2) + "\n");
    }
    function update(id, patch) {
        layouts = layouts.map(l => l.id === id ? Object.assign({}, l, patch) : l);
        save();
    }
    // Keep the live arrangement in the active layout (or a new one).
    function remember(cfg) {
        if (active) update(active.id, { "outputs": cfg, "used": Date.now() });
        else {
            const l = { "id": "l" + Date.now().toString(36), "name": autoName(cfg), "used": Date.now(), "outputs": cfg };
            layouts = layouts.concat([l]);
            activeId = l.id;
            save();
        }
    }

    // ---------------------------------------------------------------- applying

    property bool wrote: false
    property string written: ""
    function kdl(cfg) {
        const lines = ["// Written by Folio (Settings, Displays) for the displays connected now.",
                       "// Folio rewrites it; change layouts there.", ""];
        const keys = Object.keys(cfg).sort();
        const eff = effective(cfg);
        if (eff !== cfg) lines.push("// The lid is closed: the built-in display is off until it opens.", "");
        for (const k of keys) {
            const c = eff[k];
            lines.push("output " + JSON.stringify(k) + " {");
            if (c.off) lines.push("    off");
            else {
                if (c.mode) lines.push("    mode " + JSON.stringify(c.mode));
                lines.push("    scale " + (+c.scale || 1));
                lines.push("    transform " + JSON.stringify(c.transform || "normal"));
                if (c.x !== null && c.x !== undefined) lines.push("    position x=" + Math.round(c.x) + " y=" + Math.round(c.y));
                if (c.vrr) lines.push("    variable-refresh-rate");
            }
            lines.push("}");
        }
        return lines.join("\n") + "\n";
    }
    // A layout as it goes on screen: the clamshell turns the built-in panel
    // off while the lid is closed and another display is on.
    function effective(cfg) {
        const keys = Object.keys(cfg);
        const isBuiltin = k => (outputFor(k) || {}).builtin === true;
        if (!(lidClosed && clamshell && keys.some(k => !isBuiltin(k) && !cfg[k].off))) return cfg;
        const c = {};
        for (const k of keys) c[k] = isBuiltin(k) ? Object.assign({}, cfg[k], { "off": true }) : cfg[k];
        return c;
    }
    property var last: null             // the last layout written, before the lid
    function rewrite() {
        if (!loaded || !available || outputs.length === 0) return;
        let cfg = last && Object.keys(last).sort().join("\n") === setKey ? last : complete(active ? active.outputs : {});
        if (!last && !active) for (const o of outputs) if (o.builtin) cfg[o.key] = Object.assign({}, cfg[o.key], { "off": false, "mode": cfg[o.key].mode || o.preferredMode });
        write(cfg);
    }
    function write(cfg) {
        const keys = Object.keys(cfg);
        if (keys.length > 0 && keys.every(k => cfg[k].off)) { console.warn("Outputs: refusing a layout with every display off"); return false; }
        last = cfg;
        const text = kdl(cfg);
        lastError = "";
        if (fixture !== "") simulate(effective(cfg));
        if (text === written) return true;
        written = text;
        wrote = true;
        kdlFile.setText(text);
        refreshLater();
        return true;
    }

    // Change one display (patch: mode, scale, transform, vrr, off, x, y) and
    // remember it. Changes that could leave a screen unreadable revert by
    // themselves unless kept.
    property var keep: null             // {toast, cfg}: the last layout known to be good
    function change(key, patch) {
        const before = snapshot();
        const cfg = complete(active ? active.outputs : {});
        if (!cfg[key]) return false;
        cfg[key] = Object.assign({}, cfg[key], patch);
        if (patch.off === false && !cfg[key].mode) cfg[key].mode = (outputFor(key) || {}).preferredMode || "";
        if (patch.off === true && Object.keys(cfg).every(k => cfg[k].off)) return false;
        const risky = ["mode", "scale", "transform", "off"].some(p => p in patch);
        if (!write(cfg)) return false;
        remember(cfg);
        if (risky) offerKeep(before);
        return true;
    }
    function arrange(positions) {
        const cfg = complete(active ? active.outputs : {});
        for (const k in positions) if (cfg[k]) { cfg[k].x = positions[k].x; cfg[k].y = positions[k].y; }
        if (!write(cfg)) return false;
        remember(cfg);
        return true;
    }
    function offerKeep(before) {
        let good = before;
        if (keep) { good = keep.cfg; Toasts.take(keep.toast); }
        const t = Toasts.show("Reverting display changes", {
            "icon": "display", "action": "Keep", "countdown": true, "timeout": 15000,
            "onAction": () => { root.keep = null; },
            "onTimeout": () => { root.keep = null; root.revertTo(good); }
        });
        keep = { "toast": t, "cfg": good };
    }
    function keepChanges() { if (keep) Toasts.act(keep.toast); }
    function revertTo(cfg) { if (write(cfg)) { if (active) update(active.id, { "outputs": cfg }); } }

    function choose(id) {
        const l = layouts.find(x => x.id === id);
        if (!l || setOf(l) !== setKey) return false;
        if (!write(l.outputs)) return false;
        activeId = l.id;
        update(l.id, { "used": Date.now() });
        return true;
    }
    // The next layout for these displays, in name order, announced.
    function cycle() {
        const list = current.slice().sort((a, b) => a.name.localeCompare(b.name));
        if (list.length === 0) return "";
        const pick = list[(list.findIndex(l => l.id === activeId) + 1) % list.length];
        if (pick.id !== activeId) choose(pick.id);
        applied(pick.name);
        return pick.name;
    }
    function saveAs(name) {
        const cfg = complete(active ? active.outputs : {});
        const l = { "id": "l" + Date.now().toString(36), "name": name || autoName(cfg), "used": Date.now(), "outputs": cfg };
        layouts = layouts.concat([l]);
        activeId = l.id;
        save();
        return l.id;
    }
    function rename(id, name) { if (name.trim()) update(id, { "name": name.trim() }); }
    function forget(id) {
        const l = layouts.find(x => x.id === id);
        if (!l) return;
        const was = activeId === id;
        layouts = layouts.filter(x => x.id !== id);
        if (was) activeId = "";
        Toasts.undo("Layout “" + l.name + "” forgotten", () => root.save(), () => {
            root.layouts = root.layouts.concat([l]);
            if (was) root.activeId = l.id;
            root.save();
        }, "display");
    }
    function setAuto(on) { auto = on; save(); }

    // A new set of displays: bring back its latest layout, or turn every
    // display on (known ones in their last mode and scale) and let niri place them.
    function follow() {
        if (!loaded || !available || outputs.length === 0) return;
        const list = current;
        if (list.length > 0) {
            const l = auto ? list[0] : (active || null);
            if (!l) return;
            activeId = l.id;
            // Announce only what changes on screen; a first write after login is quiet.
            const differs = !same(effective(complete(l.outputs)), snapshot());
            write(l.outputs);
            if (differs) applied(l.name);
            return;
        }
        activeId = "";
        if (!auto) return;
        const cfg = {};
        for (const o of outputs) {
            const known = layouts.map(l => l.outputs[o.key]).find(c => c && !c.off);
            cfg[o.key] = { "mode": known ? known.mode : (o.on ? o.mode : o.preferredMode), "scale": known ? known.scale : o.scale,
                           "transform": known ? known.transform : o.transform, "vrr": known ? !!known.vrr : o.vrr, "x": null, "y": null, "off": false };
        }
        const differs = !same(effective(complete(cfg)), snapshot());
        write(cfg);
        if (differs) applied("");
    }
    Timer { id: followSoon; interval: 600; onTriggered: root.follow() }
    onSetKeyChanged: {
        if (keep) { Toasts.take(keep.toast); keep = null; }
        if (Quickshell.screens.length === 0) follow(); else followSoon.restart();
    }
    onLoadedChanged: followSoon.restart()

    function identify() { identifying = true; identifyEnd.restart(); }
    Timer { id: identifyEnd; interval: 3200; onTriggered: root.identifying = false }

    // ---------------------------------------------------------------- files

    Process { running: true; command: ["mkdir", "-p", root.harness ? root.runDir : root.home + "/.config/folio"] }
    // displays.json, or on first run DMS's display profiles, whichever exists.
    property string layoutsState: ""     // "", ok, missing
    property string dmsState: ""         // "", ok, missing
    property string dmsText: ""
    function settle() {
        if (loaded || layoutsState === "" || (layoutsState === "missing" && dmsState === "")) return;
        if (layoutsState === "missing" && dmsText) importDms(dmsText);
        loaded = true;
    }
    FileView {
        id: layoutsFile
        path: root.layoutsPath
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.layouts = d.layouts || [];
                root.auto = d.auto !== false;
                root.names = d.names || {};
            } catch (e) { console.warn("Outputs: unreadable", root.layoutsPath, e); }
            root.layoutsState = "ok";
            root.settle();
        }
        onLoadFailed: { root.layoutsState = "missing"; root.settle(); }
    }
    FileView {
        path: root.dmsProfiles
        printErrors: false
        onLoaded: { root.dmsText = text(); root.dmsState = "ok"; root.settle(); }
        onLoadFailed: { root.dmsState = "missing"; root.settle(); }
    }
    function importDms(text) {
        let d;
        try { d = JSON.parse(text); } catch (e) { return; }
        const out = [];
        for (const p of d.configurations || []) {
            const cfg = {};
            for (const k in p.outputs || {}) {
                const o = p.outputs[k];
                cfg[k] = { "mode": o.mode || "", "x": (o.position || {}).x || 0, "y": (o.position || {}).y || 0, "scale": o.scale || 1,
                           "transform": kdlTransform(o.transform), "vrr": !!o.vrr, "off": !!o.disabled };
            }
            if (Object.keys(cfg).length) out.push({ "id": "dms-" + out.length, "name": p.name || "Layout", "used": out.length, "outputs": cfg });
        }
        layouts = out;
        if (out.length) { console.warn("Outputs: imported", out.length, "layouts from DMS"); save(); }
    }
    FileView {
        id: kdlFile
        path: root.kdlPath
        printErrors: false
        atomicWrites: true
        onLoaded: root.written = text()
    }

    // ---------------------------------------------------------------- fixtures

    // niri's JSON for a few desks: the laptop alone, docked to an ultrawide,
    // and a crowded desk with long names, rotation and many modes.
    property var fixtureRaw: ({})
    function mk(name, make, model, serial, mm, modes, cur, x, y, scale, transform, vrr) {
        const ms = modes.map((m, i) => ({ "width": m[0], "height": m[1], "refresh_rate": m[2], "is_preferred": i === 0 }));
        const c = cur === null ? null : (cur || 0);
        const m = c === null ? null : ms[c];
        const t = transform || "Normal";
        const sw = m ? Math.round(m.width / (scale || 1)) : 0, sh = m ? Math.round(m.height / (scale || 1)) : 0;
        const rot = /90|270/.test(t);
        return { "name": name, "make": make, "model": model, "serial": serial, "physical_size": mm, "modes": ms, "current_mode": c,
                 "vrr_supported": vrr !== undefined, "vrr_enabled": !!vrr,
                 "logical": m ? { "x": x || 0, "y": y || 0, "width": rot ? sh : sw, "height": rot ? sw : sh, "scale": scale || 1, "transform": t } : null };
    }
    readonly property var laptopModes: [[1920, 1200, 60000], [1920, 1080, 60000], [1600, 1200, 60000], [1680, 1050, 60000], [1280, 800, 60000], [1024, 768, 60000]]
    function fixtures(name) {
        const lap = (cur, x, y) => mk("eDP-1", "Lenovo Group Limited", "B140UAN02.7 ", null, [300, 190], laptopModes, cur, x, y, 1, "Normal", false);
        const wide = (x, y) => mk("DP-3", "Samsung Electric Company", "LC34G55T", "HNTY602708", [800, 340],
                                  [[3440, 1440, 99982], [3440, 1440, 59973], [2560, 1440, 59951], [1920, 1080, 60000]], 0, x, y, 1, "Normal", false);
        const kvm = (x, y) => mk("HDMI-A-1", "PNP(GLI)", "GLKVM", "891247", [600, 340], [[2560, 1440, 59951], [1920, 1080, 60000]], 0, x, y, 1);
        if (name === "empty") return { "eDP-1": lap(0, 0, 0) };
        if (name === "normal") return { "eDP-1": lap(0, 0, 1440), "DP-3": wide(0, 0) };
        // stress: four displays, a portrait one, a tiny one, long names, many modes, the panel off
        const many = [];
        for (const w of [3840, 3440, 2560, 2048, 1920, 1680, 1600, 1440, 1280, 1024]) for (const hz of [143856, 119880, 59940]) many.push([w, Math.round(w * 9 / 16), hz]);
        return {
            "eDP-1": lap(null),
            "DP-3": wide(0, 0),
            "DP-4": mk("DP-4", "Dell Inc.", "DELL U2723QE Professional Ultra-High-Definition Monitor", "7XQ9QL3", [597, 336], many, 0, 3440, 0, 1.5, "_90", true),
            "HDMI-A-1": kvm(0, 1440),
            "DP-5": mk("DP-5", "PNP(IDI)", "Elgato Prom.", "0x01348D27", [155, 90], [[1024, 600, 60110]], 0, 2560, 1440, 1)
        };
    }
    function setFixture(name) {
        fixture = name;
        fixtureRaw = name ? fixtures(name) : ({});
        written = "";
        refresh();
    }
    // In fixture mode, a written layout changes the fixture as niri would.
    function simulate(cfg) {
        const raw = JSON.parse(JSON.stringify(fixtureRaw));
        let autoX = 0;
        for (const n in raw) {
            const o = raw[n], c = cfg[keyOf(o)];
            if (!c) continue;
            if (c.off) { o.current_mode = null; o.logical = null; continue; }
            const want = parseMode(c.mode);
            let idx = o.modes.findIndex(m => want && m.width === want.w && m.height === want.h && Math.abs(m.refresh_rate / 1000 - want.hz) < 0.01);
            if (idx < 0) idx = 0;
            const m = o.modes[idx];
            o.current_mode = idx;
            const t = { "normal": "Normal", "90": "_90", "180": "_180", "270": "_270" }[c.transform] || "Normal";
            const sw = Math.round(m.width / c.scale), sh = Math.round(m.height / c.scale);
            const rot = rotated(c.transform);
            const x = c.x === null || c.x === undefined ? autoX : c.x, y = c.y === null || c.y === undefined ? 0 : c.y;
            o.logical = { "x": x, "y": y, "width": rot ? sh : sw, "height": rot ? sw : sh, "scale": c.scale, "transform": t };
            o.vrr_enabled = !!c.vrr && o.vrr_supported;
            autoX = Math.max(autoX, x + o.logical.width);
        }
        fixtureRaw = raw;
        outputs = normalize(raw);
    }
    // Hotplug in fixture mode: connect or disconnect one display.
    function plug(name, on) {
        const all = fixtures("stress");
        const raw = JSON.parse(JSON.stringify(fixtureRaw));
        if (on && all[name]) raw[name] = all[name];
        if (!on) delete raw[name];
        fixtureRaw = raw;
        outputs = normalize(raw);
    }

    Component.onCompleted: refresh()
}
