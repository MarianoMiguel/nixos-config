pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "InputKdl.js" as Kdl

// Keyboard, mouse and touchpad: what niri's config says (config.kdl and every
// file it includes, read only) and Folio's own include, folio-input.kdl, which
// this service owns. config.kdl includes it after the rest, so it wins.
//
// Every change regenerates the whole file, checks it with `niri validate`
// against a scratch config that includes it, and only then writes it; niri
// reloads by itself. A change niri would reject is undone and `error` says
// why. Pointing-device sections (touchpad, mouse, trackpoint) replace the
// config's whole, so Folio writes them complete: its own settings plus
// anything else the config sets there (tap, scroll-factor…).
//
// The keymap comes from Folio's file, else the config, else the system
// keymap (localectl), which niri uses when xkb is empty. The first change
// copies it into Folio's file.
//
// In the harness and in fixtures every file lives under
// $XDG_RUNTIME_DIR/folio-input; the real ~/.config/niri is only read.
Singleton {
    id: root

    readonly property bool harness: Sys.harness
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string runDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/folio-input"
    readonly property string mainConfig: Quickshell.env("NIRI_CONFIG") || ((Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/niri/config.kdl")
    readonly property string fileName: "folio-input.kdl"
    readonly property string liveTarget: Kdl.dirname(mainConfig) + "/" + fileName
    // Fixtures keep their own file, so the harness's copy of the live one survives them.
    readonly property string target: fixture !== "" ? runDir + "/fixture-input.kdl" : (harness ? runDir + "/" + fileName : liveTarget)
    readonly property var header: [
        "Keyboard, mouse and touchpad settings from Folio's Settings. Folio rewrites",
        "this file on every change; change them there. Pointing-device sections are",
        "complete: niri replaces the ones in config.kdl with them."
    ]

    // ---------------------------------------------------------------- state

    property string fixture: ""
    property var config: ({ "nodes": [], "folioAt": -1, "files": [], "missing": [], "errors": [] })
    property var folio: ({ "xkb": null, "keyboard": {}, "devices": {} })
    property string written: ""                 // Folio's file as niri reads it
    property var system: ({ "layout": "", "variant": "", "options": "", "model": "" })
    property var catalog: ({ "layouts": [], "options": {}, "names": {} })
    property var hardware: ({ "touchpads": [], "mice": [], "trackpoints": [], "laptop": false })
    property int fixtureCurrent: 0
    property var fixtureNames: ({})
    property string error: ""                   // why the last change was not applied
    property string errorArea: ""               // layouts, typing, general, touchpad, mouse, trackpoint
    property bool checking: false
    property bool dirty: false                  // a change not yet written
    property string candidate: ""
    property string area: ""

    // UI requests from IPC (scroll to a section, search, open the picker) for the pages.
    signal request(string what, string arg)

    // ---------------------------------------------------------------- derived

    readonly property bool included: config.folioAt >= 0
    readonly property var before: config.folioAt >= 0 ? config.nodes.slice(0, config.folioAt) : config.nodes
    readonly property var after: config.folioAt >= 0 ? config.nodes.slice(config.folioAt) : []
    readonly property var base: Kdl.input(config.nodes)
    readonly property var eff: Kdl.input(after, Kdl.input(Kdl.folioNodes(folio), Kdl.input(before)))

    readonly property string keymapSource: folio.xkb ? "folio" : (eff.xkb.layout ? "config" : (system.layout ? "system" : "default"))
    readonly property var keymap: eff.xkb.layout ? eff.xkb : (system.layout ? system : ({ "layout": "", "variant": "", "options": eff.xkb.options || "", "model": "" }))
    readonly property var layouts: {
        const list = Kdl.layoutList(keymap.layout, keymap.variant).map(l => Object.assign(l, { "name": nameOf(l.id), "implicit": false }));
        return list.length ? list : [{ "id": "us", "layout": "us", "variant": "", "name": nameOf("us"), "implicit": true }];
    }
    readonly property int maxLayouts: 4         // xkb keeps four groups; it drops the rest
    readonly property var options: String(keymap.options || "").split(",").map(s => s.trim()).filter(s => s !== "")
    readonly property string switchOption: options.find(o => o.indexOf("grp:") === 0) || ""
    readonly property string composeOption: options.find(o => o.indexOf("compose:") === 0) || ""
    readonly property int currentLayout: fixture !== "" ? fixtureCurrent : (Niri.layouts.length === layouts.length ? Niri.layoutIndex : -1)

    readonly property int repeatDelay: eff.keyboard["repeat-delay"] !== undefined ? eff.keyboard["repeat-delay"] : 600
    readonly property int repeatRate: eff.keyboard["repeat-rate"] !== undefined ? eff.keyboard["repeat-rate"] : 25
    readonly property bool numlock: eff.keyboard.numlock === true
    readonly property string trackLayout: eff.keyboard["track-layout"] || "global"

    readonly property var touchpad: Kdl.values(eff.devices.touchpad || [])
    readonly property var mouse: Kdl.values(eff.devices.mouse || [])
    readonly property var trackpoint: Kdl.values(eff.devices.trackpoint || [])
    readonly property bool leftHanded: !!(mouse["left-handed"] || touchpad["left-handed"])

    readonly property bool hasTouchpad: hardware.touchpads.length > 0 || hardware.laptop
    readonly property bool hasMouse: hardware.mice.length > 0
    readonly property bool hasTrackpoint: hardware.trackpoints.length > 0

    readonly property string modKey: eff.modKey || "Super"
    readonly property var shortcuts: Kdl.shortcuts(config.nodes, modKey)
    readonly property var groups: ["Apps & shell", "Windows", "Focus & move", "Sizing", "Workspaces", "Displays", "Screenshots & sharing", "Media keys", "Mouse & scroll", "System", "Other"]

    function nameOf(id) { return fixtureNames[id] || catalog.names[id] || id; }
    function optionName(id) { return catalog.options[id] || id; }

    // ---------------------------------------------------------------- reading

    Component { id: reader; FileView { blockAllReads: true; printErrors: false } }
    function readSync(path) {
        const f = reader.createObject(root, { "path": path });
        const t = f.text();
        const ok = f.loaded;
        f.destroy();
        return ok ? t : null;
    }

    function readConfig() {
        if (fixture !== "") {
            const files = fixtureFiles;
            config = Kdl.flatten(p => files[p] !== undefined ? files[p] : null, "/fixture/niri/config.kdl", "/fixture", fileName);
        } else {
            config = Kdl.flatten(readSync, mainConfig, home, fileName);
        }
        if (config.errors.length) console.warn("Input: config:", config.errors.join("; "));
    }
    function readHardware() {
        if (fixture !== "") return;
        const battery = ["BAT0", "BAT1", "BAT2"].some(b => readSync("/sys/class/power_supply/" + b + "/type") !== null);
        hardware = Object.assign(Kdl.devices(readSync("/proc/bus/input/devices") || ""),
                                 { "laptop": Kdl.isLaptop(readSync("/sys/class/dmi/id/chassis_type") || "", battery) });
    }
    // Everything the pages show, read again (pages call it when they open).
    function refresh() {
        readConfig();
        readHardware();
        if (fixture === "" && !localectl.running) localectl.running = true;
        if (!catalogProc.running && catalog.layouts.length === 0) catalogProc.running = true;
    }

    Process {
        id: localectl
        command: ["localectl", "status"]
        stdout: StdioCollector { onStreamFinished: if (root.fixture === "") root.system = Kdl.localed(text) }
    }
    // xkb's list of layouts, variants and options: wherever libxkbcommon finds it.
    Process {
        id: catalogProc
        command: ["sh", "-c", "for d in \"$XKB_CONFIG_ROOT\" /usr/share/X11/xkb /etc/X11/xkb /run/current-system/sw/share/X11/xkb; do "
            + "[ -n \"$d\" ] && [ -f \"$d/rules/evdev.lst\" ] && exec cat \"$d/rules/evdev.lst\"; done; "
            + "lib=$(ldd \"$(readlink -f \"$(command -v niri)\")\" 2>/dev/null | awk '/libxkbcommon/ {print $3; exit}'); "
            + "d=$([ -n \"$lib\" ] && grep -ao '/nix/store/[a-z0-9]*-xkeyboard-config-[^/]*/share/X11/xkb' \"$lib\" | head -1); "
            + "[ -n \"$d\" ] && [ -f \"$d/rules/evdev.lst\" ] && exec cat \"$d/rules/evdev.lst\"; "
            + "f=$(ls -d /nix/store/*-xkeyboard-config-*/share/X11/xkb/rules/evdev.lst 2>/dev/null | tail -1); [ -n \"$f\" ] && exec cat \"$f\""]
        stdout: StdioCollector { onStreamFinished: { const c = Kdl.catalog(text); if (c.layouts.length) root.catalog = c; else console.warn("Input: no xkb layout list found"); } }
    }
    // Hotplug: a mouse plugged in or out.
    Process {
        running: !root.harness && root.fixture === ""
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=input"]
        stdout: SplitParser { onRead: line => { if (/ (add|remove) /.test(line)) hotplug.restart(); } }
    }
    Timer { id: hotplug; interval: 500; onTriggered: root.readHardware() }
    Connections {
        target: Niri
        function onConfigLoaded(failed) {
            if (root.fixture !== "") return;
            root.readConfig();
            if (failed && root.wroteAt > 0 && Date.now() - root.wroteAt < 4000) {
                root.error = "niri could not load the new settings; it kept the previous ones.";
                root.errorArea = root.area;
                console.warn("Input:", root.error);
            }
        }
    }

    FileView {
        id: folioFile
        path: root.target
        watchChanges: true
        printErrors: false
        atomicWrites: true
        blockWrites: true
        onFileChanged: reload()
        onLoaded: root.adopt(text())
        onLoadFailed: root.adopt("")
    }
    // Folio's file as read; ignored while a change of ours is on its way, and
    // in fixtures (only this service writes it there).
    function adopt(text) {
        if (fixture !== "" || dirty || checking) return;
        written = text;
        folio = Kdl.folioState(text);
    }
    // The harness starts from a copy of Folio's real file (read, never written),
    // made once: hot reloads keep the copy and what tests changed in it.
    function seed() {
        const t = readSync(liveTarget) || "";
        written = t;
        folio = Kdl.folioState(t);
        folioFile.setText(t);
    }
    Process {
        running: true
        command: ["mkdir", "-p", root.runDir]
        onExited: if (root.harness && root.fixture === "" && root.readSync(root.runDir + "/" + root.fileName) === null) root.seed()
    }

    // ---------------------------------------------------------------- writing

    property real wroteAt: 0
    function kdl() { return Kdl.folioText(folio, header); }
    function commit(where) {
        area = where;
        dirty = true;
        writeSoon.restart();
    }
    Timer { id: writeSoon; interval: 180; onTriggered: root.check() }

    // niri does not know xkb names; check them against xkb's own list.
    function xkbProblem() {
        if (!folio.xkb || catalog.layouts.length === 0) return "";
        for (const l of Kdl.layoutList(folio.xkb.layout, folio.xkb.variant))
            if (!catalog.names[l.id]) return "xkb has no layout “" + l.id + "”.";
        for (const o of String(folio.xkb.options || "").split(",").filter(s => s))
            if (!catalog.options[o]) return "xkb has no option “" + o + "”.";
        return "";
    }
    function check() {
        if (checking) { writeSoon.restart(); return; }
        const text = kdl();
        if (text === written) { dirty = false; error = ""; return; }
        const bad = xkbProblem();
        if (bad) { fail(bad); return; }
        checking = true;
        candidate = text;
        validator.command = ["sh", "-c", "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$1/candidate.kdl\" && printf 'include \"candidate.kdl\"\\n' > \"$1/check.kdl\" && exec niri validate -c \"$1/check.kdl\"",
                             "sh", runDir, text];
        validator.running = true;
    }
    Process {
        id: validator
        stdout: StdioCollector { id: validOut }
        stderr: StdioCollector { id: validErr }
        onExited: (code, status) => root.checked(code, validErr.text + "\n" + validOut.text)
    }
    function checked(code, output) {
        checking = false;
        if (code !== 0) { fail(code === 127 ? "niri is not installed, so the change could not be checked." : summarize(output)); return; }
        error = "";
        written = candidate;
        wroteAt = Date.now();
        folioFile.setText(candidate);
        if (kdl() !== candidate) writeSoon.restart();
        else dirty = false;
    }
    // niri's report, down to the line that says what is wrong.
    function summarize(output) {
        const clean = String(output).replace(/\x1b\[[0-9;]*m/g, "");
        const generic = /error loading config|error parsing|failed to parse included config/i;
        const lines = clean.split("\n").map(l => (/×\s*(.*)$/.exec(l) || [])[1]).filter(l => l && !generic.test(l));
        return "niri rejected it: " + (lines.length ? lines[lines.length - 1].trim() : (clean.trim().split("\n").pop() || "unknown error"));
    }
    function fail(message) {
        error = message;
        errorArea = area;
        dirty = false;
        folio = Kdl.folioState(written);
        console.warn("Input:", message);
    }
    function dismissError() { error = ""; }

    // ---------------------------------------------------------------- changes

    function setKeyboard(key, value) {
        const kb = Object.assign({}, folio.keyboard);
        kb[key] = value;
        folio = Object.assign({}, folio, { "keyboard": kb });
        commit("typing");
    }
    function setKeymap(list, opts) {
        const j = Kdl.joinLayouts(list);
        folio = Object.assign({}, folio, { "xkb": { "layout": j.layout, "variant": j.variant, "options": opts.join(","), "model": keymap.model || "" } });
        commit("layouts");
    }
    function addLayout(id) {
        if (layouts.some(l => l.id === id) || layouts.length >= maxLayouts) return false;
        setKeymap(layouts.concat([Kdl.splitId(id)]), options);
        return true;
    }
    function removeLayout(index) {
        if (layouts.length <= 1 || index < 0 || index >= layouts.length) return false;
        const was = folio, gone = layouts[index];
        setKeymap(layouts.filter((l, k) => k !== index), options);
        Toasts.undo("Removed " + gone.name, () => {}, () => { root.folio = was; root.commit("layouts"); }, "keyboard");
        return true;
    }
    function moveLayout(index, delta) {
        const j = index + delta;
        if (index < 0 || j < 0 || j >= layouts.length) return false;
        const list = layouts.slice();
        const t = list[index]; list[index] = list[j]; list[j] = t;
        setKeymap(list, options);
        return true;
    }
    // One option of a kind ("grp", "compose"); "" removes it.
    function setOption(prefix, value) {
        const opts = options.filter(o => o.indexOf(prefix + ":") !== 0);
        if (value) opts.push(value);
        setKeymap(layouts, opts);
    }
    function switchTo(index) {
        if (index < 0 || index >= layouts.length) return;
        if (fixture !== "") fixtureCurrent = index;
        else Sys.run(["niri", "msg", "action", "switch-layout", String(index)]);
    }

    // A pointing-device setting: the device's whole section is rewritten.
    function setDevice(device, key, value) { setDevices([device], key, value, device); }
    function setDevices(list, key, value, where) {
        const ds = Object.assign({}, folio.devices);
        for (const d of list) {
            const vals = Kdl.values(eff.devices[d] || []);
            vals[key] = value;
            ds[d] = Kdl.section(d, vals, base.devices[d] || []);
        }
        folio = Object.assign({}, folio, { "devices": ds });
        commit(where);
    }
    function setPrimary(right) { setDevices(["touchpad", "mouse", "trackpoint"], "left-handed", right, "general"); }

    // ---------------------------------------------------------------- fixtures

    property var fixtureFiles: ({})
    function setFixture(name) {
        const f = name ? fixtures(name) : null;
        fixture = f ? name : "";
        fixtureFiles = f ? f.files : ({});
        fixtureNames = f ? (f.names || {}) : ({});
        fixtureCurrent = f ? f.current : 0;
        error = "";
        dirty = false;
        if (f) {
            system = f.system;
            hardware = f.hardware;
            folio = Kdl.folioState(f.folio);
            written = f.folio;
            folioFile.setText(f.folio);
        } else {
            system = ({ "layout": "", "variant": "", "options": "", "model": "" });
            if (harness) seed(); else folioFile.reload();
        }
        refresh();
    }

    function fixtures(name) {
        const cfg = (inputBlock, bindsBlock, extra) => [
            "// A fixture standing in for ~/.config/niri/config.kdl.",
            "input {", inputBlock, "    focus-follows-mouse max-scroll-amount=\"0%\"", "}",
            extra || "",
            // After the include, so these win over the same keys there.
            "binds {", bindsBlock, "}",
            "include optional=true \"folio-input.kdl\"", ""
        ].join("\n");
        const shellBinds = [
            "    Mod+Space repeat=false hotkey-overlay-title=\"Search and Actions\" { spawn \"mariano-shell\" \"ipc\" \"launcher\" \"toggle\"; }",
            "    Mod+N repeat=false hotkey-overlay-title=\"Sidebar\" { spawn \"mariano-shell\" \"ipc\" \"sidebar\" \"toggle\"; }",
            "    Mod+Comma repeat=false hotkey-overlay-title=\"Appearance\" { spawn \"mariano-shell\" \"ipc\" \"appearance\" \"toggle\"; }",
            "    Mod+T hotkey-overlay-title=\"Open Terminal\" { spawn \"ghostty\"; }",
            "    Super+B hotkey-overlay-title=\"Open <b>Browser</b>\" { spawn \"google-chrome-stable\"; }",
            "    Mod+Alt+L hotkey-overlay-title=\"Lock\" { spawn \"mariano-shell\" \"ipc\" \"lock\" \"lock\"; }",
            "    XF86AudioRaiseVolume allow-when-locked=true { spawn \"mariano-shell\" \"ipc\" \"osd\" \"volumeUp\"; }",
            "    XF86AudioLowerVolume allow-when-locked=true { spawn \"mariano-shell\" \"ipc\" \"osd\" \"volumeDown\"; }",
            "    XF86AudioMute allow-when-locked=true { spawn \"mariano-shell\" \"ipc\" \"osd\" \"mute\"; }",
            "    XF86MonBrightnessUp allow-when-locked=true { spawn \"mariano-shell\" \"ipc\" \"osd\" \"brightnessUp\"; }"
        ].join("\n");
        const niriBinds = [
            "binds {",
            "    Mod+D repeat=false { toggle-overview; }",
            "    Mod+Shift+Slash { show-hotkey-overlay; }",
            "    Mod+Q repeat=false { close-window; }",
            "    Mod+F { maximize-column; }",
            "    Mod+Shift+F { fullscreen-window; }",
            "    Mod+Shift+T { toggle-window-floating; }",
            "    Mod+W { toggle-column-tabbed-display; }",
            "    Mod+Left { focus-column-left; }",
            "    Mod+Right { focus-column-right; }",
            "    Mod+Up { focus-window-up; }",
            "    Mod+Down { focus-window-down; }",
            "    Mod+Shift+Left { move-column-left; }",
            "    Mod+Shift+Right { move-column-right; }",
            "    Mod+R { switch-preset-column-width; }",
            "    Mod+Minus { set-column-width \"-10%\"; }",
            "    Mod+Equal { set-column-width \"+10%\"; }",
            "    Mod+1 { focus-workspace 1; }",
            "    Mod+2 { focus-workspace 2; }",
            "    Mod+3 { focus-workspace 3; }",
            "    Mod+Shift+1 { move-column-to-workspace 1; }",
            "    Mod+Page_Down { focus-workspace-down; }",
            "    Ctrl+Left { focus-monitor-left; }",
            "    Ctrl+Shift+Right { move-window-to-monitor-right; }",
            "    Print { screenshot; }",
            "    Alt+Shift+4 repeat=false hotkey-overlay-title=\"Capture Region\" { spawn \"mariano-capture\" \"screenshot-region\"; }",
            "    Mod+WheelScrollDown cooldown-ms=150 { focus-workspace-down; }",
            "    Mod+WheelScrollUp cooldown-ms=150 { focus-workspace-up; }",
            "    Mod+Shift+E { quit; }",
            // config.kdl binds Mod+T again after including this file, and wins.
            "    Mod+T { spawn \"alacritty\"; }",
            "}", ""
        ].join("\n");
        const lapHw = { "touchpads": ["ELAN0678:00 04F3:3195 Touchpad"], "mice": ["Logitech MX Master 3S"], "trackpoints": ["TPPS/2 Elan TrackPoint"], "laptop": true };

        if (name === "empty") return {
            "files": { "/fixture/niri/config.kdl": cfg("    keyboard {\n        xkb {\n        }\n    }", "") },
            "folio": "", "current": 0,
            "system": { "layout": "", "variant": "", "options": "", "model": "" },
            "hardware": { "touchpads": [], "mice": [], "trackpoints": [], "laptop": false }
        };
        if (name === "stress") {
            const mods = ["Mod", "Mod+Shift", "Mod+Ctrl", "Mod+Alt", "Mod+Ctrl+Shift", "Mod+Alt+Shift", "Ctrl+Alt", "Mod+Ctrl+Alt+Shift"];
            const keys = "A B C D E F G H I J K L M N O P Q R S T U V W X Y Z 0 1 2 3 4 5 6 7 8 9 F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12".split(" ");
            const acts = ["focus-workspace", "move-column-to-workspace", "move-window-to-workspace", "set-column-width", "focus-column-left", "move-window-to-monitor-right", "spawn"];
            const lines = [];
            let k = 0;
            for (const m of mods) for (const key of keys) {
                if (k >= 330) break;
                const a = acts[k % acts.length];
                const long = k % 9 === 0 ? " hotkey-overlay-title=\"A deliberately long shortcut title, well past ninety characters, that keeps going to test eliding " + k + "\"" : "";
                const body = a === "spawn" ? "spawn \"some-very-long-command-name-for-testing\" \"--with\" \"many\" \"arguments\" \"" + k + "\""
                           : (a.indexOf("workspace") >= 0 ? a + " " + (k % 99 + 1) : (a === "set-column-width" ? a + " \"+" + (k % 50) + "%\"" : a));
                lines.push("    " + m + "+" + key + long + " { " + body + "; }");
                k++;
            }
            return {
                "files": {
                    "/fixture/niri/config.kdl": cfg("    keyboard {\n        xkb {\n            layout \"us,pl,hu,lk,brai,de\"\n            variant \"alt-intl,dvorak_quotes,102_qwertz_comma_nodead,tam_TAB,right_hand_invert,\"\n            options \"grp:alt_shift_toggle,compose:menu,ctrl:nocaps,lv3:ralt_switch\"\n        }\n        repeat-delay 250\n        repeat-rate 60\n    }\n    touchpad {\n        tap\n        scroll-factor 0.6\n        tap-button-map \"left-middle-right\"\n    }\n    mouse {\n        scroll-factor vertical=1.0 horizontal=-2.0\n    }",
                                                     shellBinds + "\n" + lines.join("\n"), "include \"binds.kdl\""),
                    "/fixture/niri/binds.kdl": niriBinds
                },
                "folio": "", "current": 3,
                "names": { "us(alt-intl)": "English (US, alternative international with dead keys, AltGr dead keys and a very long name)" },
                "system": { "layout": "us", "variant": "", "options": "", "model": "pc105" },
                "hardware": {
                    "touchpads": ["Synaptics TM3418-002 Precision Touchpad with a very long device name from the firmware", "ELAN0678:00 04F3:3195 Touchpad"],
                    "mice": ["Logitech MX Master 3S for Business (Bolt receiver) with a long product name", "Razer DeathAdder V3 Pro", "Kensington Expert Wireless Trackball"],
                    "trackpoints": ["TPPS/2 Elan TrackPoint"], "laptop": true
                }
            };
        }
        // normal: a laptop docked to a mouse; Folio already owns layouts and the touchpad.
        return {
            "files": {
                "/fixture/niri/config.kdl": cfg("    keyboard {\n        xkb {\n        }\n        numlock\n    }\n    touchpad {\n        tap\n    }\n    mouse {\n    }", shellBinds, "include \"binds.kdl\""),
                "/fixture/niri/binds.kdl": niriBinds
            },
            "folio": Kdl.folioText({
                "xkb": { "layout": "us,es", "variant": ",", "options": "grp:shift_caps_toggle,compose:ralt", "model": "pc104" },
                "keyboard": { "repeat-delay": 400, "repeat-rate": 35 },
                "devices": { "touchpad": Kdl.section("touchpad", { "tap": true, "natural-scroll": true, "dwt": true, "accel-speed": 0.2, "scroll-method": "two-finger", "click-method": "clickfinger" }, []) }
            }, header),
            "current": 0,
            "system": { "layout": "us,es", "variant": ",", "options": "grp:shift_caps_toggle,compose:ralt", "model": "pc104" },
            "hardware": lapHw
        };
    }

    // ---------------------------------------------------------------- IPC

    function parseValue(v) {
        if (v === "true") return true;
        if (v === "false") return false;
        if (v === "" || v === "null") return null;
        if (/^-?\d+(\.\d+)?$/.test(v)) return parseFloat(v);
        return v;
    }
    function snapshot() {
        return {
            "fixture": fixture, "target": target, "included": included, "files": config.files, "missing": config.missing, "configErrors": config.errors,
            "keymapSource": keymapSource, "layouts": layouts.map(l => l.id + " " + l.name), "current": currentLayout, "options": options,
            "repeatDelay": repeatDelay, "repeatRate": repeatRate, "numlock": numlock, "trackLayout": trackLayout,
            "touchpad": touchpad, "mouse": mouse, "trackpoint": trackpoint, "hardware": hardware,
            "shortcuts": shortcuts.length, "catalog": catalog.layouts.length, "error": error, "dirty": dirty, "checking": checking
        };
    }

    IpcHandler {
        target: "input"
        // normal, stress, empty; "" for the live config.
        function fixture(name: string): string { root.setFixture(name); return root.fixture || "live"; }
        // The file Folio would write for the current state, and the one written.
        function kdl(): string { return root.kdl(); }
        function written(): string { return root.written; }
        function path(): string { return root.target; }
        function state(): string { return JSON.stringify(root.snapshot(), null, 1); }
        function error(): string { return root.error; }
        // set touchpad tap false; set mouse accel-speed -0.4
        function set(device: string, key: string, value: string): string { root.setDevice(device, key, root.parseValue(value)); return root.kdl(); }
        // keyboard repeat-delay 300; keyboard numlock false
        function keyboard(key: string, value: string): string { root.setKeyboard(key, root.parseValue(value)); return root.kdl(); }
        function addLayout(id: string): bool { return root.addLayout(id); }
        function removeLayout(index: int): bool { return root.removeLayout(index); }
        function moveLayout(index: int, delta: int): bool { return root.moveLayout(index, delta); }
        // option grp grp:alt_shift_toggle; option compose ""
        function option(prefix: string, value: string): string { root.setOption(prefix, value); return root.kdl(); }
        function primary(side: string): void { root.setPrimary(side === "right"); }
        function current(index: int): void { root.switchTo(index); }
        // Page requests: ui scroll shortcuts; ui search ctrl; ui picker spanish; ui switch open; ui group Workspaces
        function ui(what: string, arg: string): void { root.request(what, arg); }
    }

    Component.onCompleted: refresh()
}
