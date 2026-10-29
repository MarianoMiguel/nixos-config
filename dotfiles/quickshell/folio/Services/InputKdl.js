.pragma library

// Pure helpers for Services/Input.qml: a small KDL reader and writer (the
// subset niri's config uses), niri's include and merge rules for `input` and
// `binds`, the xkb catalog (rules/evdev.lst), /proc/bus/input/devices, and
// readable names for keybinds. No QML here, so it can be tested on its own.

// ------------------------------------------------------------------ KDL

const NL = "\n\r\u0085  \f";
const SPACE = " \t﻿               　";
const NOT_IDENT = "\\/(){}<>;[]=,\"";

// parse(text) -> { nodes: [{name, args, props, children}], error }
// children is null when the node has no block. Lenient: an error stops the
// parse and returns what was read so far.
function parse(src) {
    src = String(src || "");
    let i = 0, error = "";
    const n = src.length;
    const isNl = c => c !== undefined && NL.indexOf(c) >= 0;
    const isSpace = c => c !== undefined && SPACE.indexOf(c) >= 0;
    const isIdent = c => c !== undefined && !isNl(c) && !isSpace(c) && NOT_IDENT.indexOf(c) < 0;
    function lineAt(p) { return src.slice(0, p).split("\n").length; }
    function fail(msg) { if (!error) error = msg + " (line " + lineAt(i) + ")"; i = n; }

    function blockComment() {
        let depth = 0;
        while (i < n) {
            if (src.startsWith("/*", i)) { depth++; i += 2; }
            else if (src.startsWith("*/", i)) { depth--; i += 2; if (depth === 0) return; }
            else i++;
        }
    }
    // Spaces, block comments and line continuations; not newlines.
    function inline() {
        for (;;) {
            const c = src[i];
            if (isSpace(c)) i++;
            else if (src.startsWith("/*", i)) blockComment();
            else if (c === "\\") {
                // Line continuation: backslash, optional space or comment, newline.
                let j = i + 1;
                while (isSpace(src[j])) j++;
                if (src.startsWith("//", j)) while (j < n && !isNl(src[j])) j++;
                if (isNl(src[j])) { i = j + (src[j] === "\r" && src[j + 1] === "\n" ? 2 : 1); }
                else return;
            } else return;
        }
    }
    function lineComment() { while (i < n && !isNl(src[i])) i++; }
    // Everything between nodes: spaces, newlines, comments, semicolons.
    function between() {
        for (;;) {
            inline();
            const c = src[i];
            if (isNl(c) || c === ";") i++;
            else if (src.startsWith("//", i)) lineComment();
            else return;
        }
    }
    function typeAnnotation() {
        if (src[i] !== "(") return;
        const j = src.indexOf(")", i);
        if (j < 0) return fail("unclosed type annotation");
        i = j + 1;
    }
    function quoted() {
        i++;                                // opening quote
        let out = "";
        while (i < n) {
            const c = src[i];
            if (c === "\"") { i++; return out; }
            if (c === "\\") {
                const e = src[i + 1];
                const map = { "n": "\n", "r": "\r", "t": "\t", "\\": "\\", "/": "/", "\"": "\"", "b": "\b", "f": "\f", "s": " " };
                if (e === "u" && src[i + 2] === "{") {
                    const j = src.indexOf("}", i);
                    out += String.fromCodePoint(parseInt(src.slice(i + 3, j), 16) || 0xFFFD);
                    i = j + 1;
                    continue;
                }
                if (isSpace(e) || isNl(e)) {        // KDL 2 whitespace escape
                    i++;
                    while (isSpace(src[i]) || isNl(src[i])) i++;
                    continue;
                }
                out += map[e] !== undefined ? map[e] : e;
                i += 2;
                continue;
            }
            out += c;
            i++;
        }
        fail("unclosed string");
        return out;
    }
    function raw() {
        // r"..." / r#"..."# (KDL 1) and #"..."# (KDL 2)
        if (src[i] === "r") i++;
        let hashes = 0;
        while (src[i] === "#") { hashes++; i++; }
        if (src[i] !== "\"") { fail("bad raw string"); return ""; }
        i++;
        const close = "\"" + "#".repeat(hashes);
        const j = src.indexOf(close, i);
        if (j < 0) { fail("unclosed raw string"); return ""; }
        const out = src.slice(i, j);
        i = j + close.length;
        return out;
    }
    function isRawStart() {
        if (src[i] === "r" && (src[i + 1] === "\"" || src[i + 1] === "#")) {
            let j = i + 1;
            while (src[j] === "#") j++;
            return src[j] === "\"";
        }
        if (src[i] === "#") {
            let j = i;
            while (src[j] === "#") j++;
            return src[j] === "\"";
        }
        return false;
    }
    function bare() {
        const s = i;
        while (i < n && isIdent(src[i])) i++;
        return src.slice(s, i);
    }
    // A string (quoted, raw or bare identifier) or null.
    function stringish() {
        if (src[i] === "\"") return { "s": quoted(), "q": true };
        if (isRawStart()) return { "s": raw(), "q": true };
        const b = bare();
        return b ? { "s": b, "q": false } : null;
    }
    function scalar(tok) {
        if (tok.q) return tok.s;
        const s = tok.s;
        if (s === "true" || s === "#true") return true;
        if (s === "false" || s === "#false") return false;
        if (s === "null" || s === "#null") return null;
        const num = s.replace(/_/g, "");
        if (/^[+-]?0x[0-9a-fA-F]+$/.test(num)) return parseInt(num, 16);
        if (/^[+-]?0o[0-7]+$/.test(num)) return parseInt(num.replace("0o", ""), 8);
        if (/^[+-]?0b[01]+$/.test(num)) return parseInt(num.replace("0b", ""), 2);
        if (/^[+-]?(\d+)(\.\d+)?([eE][+-]?\d+)?$/.test(num)) return parseFloat(num);
        return s;                           // KDL 2 bare string
    }
    function node() {
        typeAnnotation();
        const nameTok = stringish();
        if (!nameTok) { fail("expected a node name, found " + JSON.stringify(src[i] || "end")); return null; }
        const nd = { "name": nameTok.s, "args": [], "props": {}, "children": null };
        for (;;) {
            inline();
            const c = src[i];
            if (i >= n) break;
            if (isNl(c) || c === ";") { i++; break; }
            if (src.startsWith("//", i)) { lineComment(); continue; }
            if (c === "}") break;
            let dropped = false;
            if (src.startsWith("/-", i)) { dropped = true; i += 2; inline(); }
            if (src[i] === "{") {
                i++;
                const kids = nodes(true);
                if (!dropped) nd.children = (nd.children || []).concat(kids);
                // A children block ends the node (a dropped one may be followed by the real one).
                if (dropped) continue;
                inline();
                if (src[i] === ";" || isNl(src[i])) i++;
                else if (src.startsWith("//", i)) lineComment();
                break;
            }
            typeAnnotation();
            const tok = stringish();
            if (!tok) { fail("unexpected " + JSON.stringify(src[i])); break; }
            if (src[i] === "=") {
                i++;
                typeAnnotation();
                const v = stringish();
                if (!v) { fail("expected a value after " + tok.s + "="); break; }
                if (!dropped) nd.props[tok.s] = scalar(v);
            } else if (!dropped) nd.args.push(scalar(tok));
        }
        return nd;
    }
    function nodes(inBlock) {
        const out = [];
        for (;;) {
            between();
            if (i >= n) { if (inBlock) fail("missing }"); return out; }
            if (src[i] === "}") {
                i++;
                if (inBlock) return out;
                fail("unexpected }");
                return out;
            }
            let dropped = false;
            if (src.startsWith("/-", i)) { dropped = true; i += 2; inline(); }
            const nd = node();
            if (nd && !dropped) out.push(nd);
            if (error) return out;
        }
    }
    const result = nodes(false);
    return { "nodes": result, "error": error };
}

function quote(s) {
    return "\"" + String(s).replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/\t/g, "\\t") + "\"";
}
function value(v) {
    if (v === null || v === undefined) return "null";
    if (typeof v === "boolean") return v ? "true" : "false";
    if (typeof v === "number") return String(Math.round(v * 10000) / 10000);
    return quote(v);
}
function ident(name) { return /^[A-Za-z_][A-Za-z0-9_\-+.:]*$/.test(name) ? name : quote(name); }

// write(nodes) -> KDL text, four-space indents.
function write(list, indent) {
    indent = indent || "";
    const lines = [];
    for (const nd of list) {
        if (nd.comment !== undefined) { lines.push(indent + "// " + nd.comment); continue; }
        let line = indent + ident(nd.name);
        for (const a of nd.args || []) line += " " + value(a);
        for (const k in nd.props || {}) line += " " + ident(k) + "=" + value(nd.props[k]);
        if (nd.children) {
            if (nd.children.length === 0) line += " {}";
            else { lines.push(line + " {"); lines.push(write(nd.children, indent + "    ")); line = indent + "}"; }
        }
        lines.push(line);
    }
    return lines.join("\n");
}
function mk(name, args, children, props) {
    return { "name": name, "args": args || [], "props": props || {}, "children": children === undefined ? null : children };
}

// ------------------------------------------------------------------ includes

function dirname(p) { const k = p.lastIndexOf("/"); return k <= 0 ? "/" : p.slice(0, k); }
function basename(p) { return p.slice(p.lastIndexOf("/") + 1); }
function normalize(p) {
    const parts = [];
    for (const s of p.split("/")) {
        if (s === "" || s === ".") continue;
        if (s === "..") parts.pop(); else parts.push(s);
    }
    return "/" + parts.join("/");
}
function resolve(from, rel, home) {
    if (rel.startsWith("~/")) return normalize(home + rel.slice(1));
    if (rel.startsWith("/")) return normalize(rel);
    return normalize(dirname(from) + "/" + rel);
}
// A path for people: relative to niri's config directory when inside it.
function shortPath(p, root) { return p.startsWith(root + "/") ? p.slice(root.length + 1) : p; }

// flatten(read, main, home, folioName) -> { nodes, folioAt, files, missing, errors }
// Follows top-level includes in order (niri's positional rule). Each node gets
// .src (the file it came from). The include of Folio's own file is not read:
// its position is returned as folioAt (an index into nodes), -1 when absent.
function flatten(read, main, home, folioName) {
    const out = { "nodes": [], "folioAt": -1, "folioPath": "", "files": [], "missing": [], "errors": [] };
    const root = dirname(main);
    function load(path, depth, optional) {
        if (depth > 12) { out.errors.push(shortPath(path, root) + ": includes nest too deep"); return; }
        const text = read(path);
        if (text === null || text === undefined) { if (!optional) out.missing.push(shortPath(path, root)); return; }
        out.files.push(shortPath(path, root));
        const r = parse(text);
        if (r.error) out.errors.push(shortPath(path, root) + ": " + r.error);
        for (const nd of r.nodes) {
            if (nd.name === "include" && typeof nd.args[0] === "string") {
                const p = resolve(path, nd.args[0], home);
                if (basename(p) === folioName) { out.folioAt = out.nodes.length; out.folioPath = p; continue; }
                load(p, depth + 1, nd.props.optional === true);
                continue;
            }
            nd.src = shortPath(path, root);
            out.nodes.push(nd);
        }
    }
    load(main, 0, false);
    return out;
}

// ------------------------------------------------------------------ input

const POINTING = ["touchpad", "mouse", "trackpoint", "trackball"];

// input(nodes, into) -> { keyboard: {key: value}, xkb: {key: value}, devices: {name: [nodes]}, modKey }
// niri's merge: keyboard keys and xkb fields merge; a pointing-device section
// replaces any earlier one whole.
function input(list, into) {
    const out = into ? JSON.parse(JSON.stringify(into)) : { "keyboard": {}, "xkb": {}, "devices": {}, "modKey": "" };
    for (const top of list) {
        if (top.name !== "input" || !top.children) continue;
        for (const s of top.children) {
            if (s.name === "keyboard") {
                for (const k of s.children || []) {
                    if (k.name === "xkb") { for (const x of k.children || []) out.xkb[x.name] = x.args[0]; }
                    else out.keyboard[k.name] = k.args.length ? k.args[0] : true;
                }
            } else if (POINTING.indexOf(s.name) >= 0) out.devices[s.name] = JSON.parse(JSON.stringify(s.children || []));
            else if (s.name === "mod-key") out.modKey = s.args[0];
        }
    }
    return out;
}

// What Folio manages in each pointing section; everything else there is
// carried over from the config so Folio's complete section loses nothing.
const MANAGED = {
    "touchpad": ["tap", "drag", "drag-lock", "natural-scroll", "accel-speed", "accel-profile", "dwt", "scroll-method", "click-method", "disabled-on-external-mouse", "left-handed"],
    "mouse": ["natural-scroll", "accel-speed", "accel-profile", "left-handed"],
    "trackpoint": ["natural-scroll", "accel-speed", "accel-profile", "left-handed"],
    "trackball": ["natural-scroll", "accel-speed", "accel-profile", "left-handed"]
};
const FLAGS = ["tap", "drag-lock", "natural-scroll", "dwt", "dwtp", "disabled-on-external-mouse", "left-handed", "middle-emulation", "off", "scroll-button-lock"];

// Section nodes -> {key: value}: flags are true/false, the rest their argument.
function values(section) {
    const v = {};
    for (const nd of section || []) {
        if (FLAGS.indexOf(nd.name) >= 0) v[nd.name] = nd.args.length ? nd.args[0] !== false : true;
        else v[nd.name] = nd.args.length ? nd.args[0] : true;
    }
    return v;
}
// A complete section: Folio's values for what it manages, the config's nodes
// for the rest (in the config's order, after Folio's).
function section(device, vals, baseNodes) {
    const managed = MANAGED[device] || [];
    const out = [];
    for (const k of managed) {
        if (!(k in vals) || vals[k] === undefined || vals[k] === null) continue;
        const v = vals[k];
        if (FLAGS.indexOf(k) >= 0) { if (v) out.push(mk(k)); }
        else if (k === "drag") out.push(mk(k, [!!v]));
        else if (k === "accel-speed") out.push(mk(k, [Math.max(-1, Math.min(1, Math.round(Number(v) * 100) / 100))]));
        else out.push(mk(k, [v]));
    }
    for (const nd of baseNodes || []) if (managed.indexOf(nd.name) < 0) out.push(mk(nd.name, nd.args.slice(), nd.children, Object.assign({}, nd.props)));
    return out;
}

// Folio's state -> its file. state: { xkb: {layout, variant, options, model} | null,
// keyboard: {key: value}, devices: {name: [nodes]} }
function folioText(state, header) {
    const inputKids = [];
    const kb = [];
    const x = state.xkb;
    if (x && x.layout) {
        const xs = [mk("layout", [x.layout]), mk("variant", [x.variant || ""]), mk("options", [x.options || ""])];
        if (x.model) xs.push(mk("model", [x.model]));
        kb.push(mk("xkb", [], xs));
    }
    const keys = ["repeat-delay", "repeat-rate", "numlock", "track-layout"];
    for (const k of keys) {
        const v = (state.keyboard || {})[k];
        if (v === undefined || v === null) continue;
        if (k === "numlock") kb.push(v ? mk(k) : mk(k, [false]));
        else kb.push(mk(k, [k.startsWith("repeat") ? Math.round(v) : v]));
    }
    if (kb.length) inputKids.push(mk("keyboard", [], kb));
    for (const d of POINTING) {
        const s = (state.devices || {})[d];
        if (s) inputKids.push(mk(d, [], s));
    }
    const lines = (header || []).map(h => "// " + h);
    if (inputKids.length) { if (lines.length) lines.push(""); lines.push(write([mk("input", [], inputKids)])); }
    return lines.join("\n") + "\n";
}
// Folio's file -> its state.
function folioState(text) {
    const r = parse(text);
    const inp = input(r.nodes);
    return {
        "xkb": inp.xkb.layout ? { "layout": inp.xkb.layout, "variant": inp.xkb.variant || "", "options": inp.xkb.options || "", "model": inp.xkb.model || "" } : null,
        "keyboard": inp.keyboard,
        "devices": inp.devices,
        "error": r.error
    };
}
function folioNodes(state) { return parse(folioText(state)).nodes; }

// ------------------------------------------------------------------ xkb

function decode(s) { return s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&apos;/g, "'").replace(/&amp;/g, "&"); }

// rules/evdev.lst -> { layouts: [{id, layout, variant, name}], options: {id: name}, names: {id: name} }
function catalog(text) {
    const out = { "layouts": [], "options": {}, "names": {} };
    let part = "";
    for (const line of String(text || "").split("\n")) {
        const h = /^!\s*(\w+)/.exec(line);
        if (h) { part = h[1]; continue; }
        const m = /^\s+(\S+)\s+(.*\S)\s*$/.exec(line);
        if (!m) continue;
        const desc = decode(m[2]);
        if (part === "layout") {
            out.layouts.push({ "id": m[1], "layout": m[1], "variant": "", "name": desc });
        } else if (part === "variant") {
            const v = /^([^:]+):\s*(.*)$/.exec(desc);
            if (!v) continue;
            out.layouts.push({ "id": v[1] + "(" + m[1] + ")", "layout": v[1], "variant": m[1], "name": v[2] });
        } else if (part === "option") out.options[m[1]] = desc;
    }
    for (const l of out.layouts) out.names[l.id] = l.name;
    return out;
}
function layoutId(layout, variant) { return variant ? layout + "(" + variant + ")" : layout; }
function splitId(id) {
    const m = /^([^(]+)(?:\(([^)]*)\))?$/.exec(id || "");
    return m ? { "layout": m[1], "variant": m[2] || "" } : { "layout": id, "variant": "" };
}
// "us,es" + ",intl" -> [{id, layout, variant}]
function layoutList(layout, variant) {
    const ls = String(layout || "").split(",").map(s => s.trim());
    const vs = String(variant || "").split(",").map(s => s.trim());
    const out = [];
    for (let k = 0; k < ls.length; k++) if (ls[k]) out.push({ "id": layoutId(ls[k], vs[k] || ""), "layout": ls[k], "variant": vs[k] || "" });
    return out;
}
function joinLayouts(list) {
    return { "layout": list.map(l => l.layout).join(","), "variant": list.some(l => l.variant) ? list.map(l => l.variant).join(",") : (list.length > 1 ? list.map(() => "").join(",") : "") };
}

// `localectl status` -> {layout, variant, options, model}
function localed(text) {
    const out = { "layout": "", "variant": "", "options": "", "model": "" };
    const keys = { "X11 Layout": "layout", "X11 Variant": "variant", "X11 Options": "options", "X11 Model": "model" };
    for (const line of String(text || "").split("\n")) {
        const m = /^\s*(X11 \w+):\s*(.*?)\s*$/.exec(line);
        if (m && keys[m[1]] && m[2] !== "(unset)" && m[2] !== "n/a") out[keys[m[1]]] = m[2];
    }
    return out;
}

// ------------------------------------------------------------------ devices

// One bit of a /proc bitmap ("e520 10000 0 0 0 0", most significant word first, 64-bit words).
function bit(map, b) {
    const words = String(map || "0").trim().split(/\s+/).reverse();
    const w = words[Math.floor(b / 64)];
    if (!w) return false;
    const k = Math.floor((b % 64) / 4);
    const c = w[w.length - 1 - k];
    return !!c && ((parseInt(c, 16) >> (b % 4)) & 1) === 1;
}
// /proc/bus/input/devices -> { touchpads: [names], mice: [names], trackpoints: [names] }
function devices(text) {
    const list = [];
    for (const block of String(text || "").split(/\n\s*\n/)) {
        const d = { "name": "", "bus": "", "vendor": "", "product": "", "phys": "", "sysfs": "", "prop": "0", "key": "0", "rel": "0", "abs": "0" };
        for (const line of block.split("\n")) {
            let m;
            if ((m = /^I: Bus=(\w+) Vendor=(\w+) Product=(\w+)/.exec(line))) { d.bus = m[1]; d.vendor = m[2]; d.product = m[3]; }
            else if ((m = /^N: Name="(.*)"$/.exec(line))) d.name = m[1];
            else if ((m = /^P: Phys=(.*)$/.exec(line))) d.phys = m[1];
            else if ((m = /^S: Sysfs=(.*)$/.exec(line))) d.sysfs = m[1];
            else if ((m = /^B: (PROP|KEY|REL|ABS)=(.*)$/.exec(line))) d[m[1].toLowerCase()] = m[2];
        }
        if (d.name) list.push(d);
    }
    const out = { "touchpads": [], "mice": [], "trackpoints": [] };
    const pads = [];
    for (const d of list) {
        const virtual = d.sysfs.indexOf("/devices/virtual/") >= 0;
        if (virtual) continue;
        const stick = bit(d.prop, 5) || /trackpoint|pointing ?stick|pointstick/i.test(d.name);
        const pad = !stick && ((bit(d.key, 0x145) && bit(d.abs, 0) && !bit(d.prop, 1) && !bit(d.key, 0x140)) || /touchpad|trackpad|clickpad/i.test(d.name));
        if (stick) out.trackpoints.push(d.name);
        else if (pad) { out.touchpads.push(d.name); pads.push(d); }
    }
    for (const d of list) {
        if (d.sysfs.indexOf("/devices/virtual/") >= 0) continue;
        if (out.touchpads.indexOf(d.name) >= 0 || out.trackpoints.indexOf(d.name) >= 0) continue;
        const pointer = bit(d.rel, 0) && bit(d.rel, 1) && bit(d.key, 0x110);
        if (!pointer || bit(d.prop, 5)) continue;
        // A touchpad's own mouse node (same chip) is not a mouse.
        if (pads.some(p => (p.phys && p.phys === d.phys) || (p.vendor === d.vendor && p.product === d.product && p.bus === d.bus))) continue;
        out.mice.push(d.name);
    }
    return out;
}
function isLaptop(chassis, battery) { return battery || [8, 9, 10, 11, 14, 30, 31, 32].indexOf(parseInt(chassis, 10)) >= 0; }

// ------------------------------------------------------------------ binds

const MOD_ALIASES = { "control": "ctrl", "win": "super", "mod5": "iso_level3_shift", "iso_level3_shift": "iso_level3_shift" };
const MOD_NAMES = ["mod", "super", "ctrl", "alt", "shift", "iso_level3_shift", "iso_level5_shift", "mod3"];
function keyNorm(name) {
    const parts = String(name).split("+");
    const key = parts.pop().toLowerCase();
    const mods = parts.map(p => { const l = p.toLowerCase(); return MOD_ALIASES[l] || l; });
    mods.sort((a, b) => MOD_NAMES.indexOf(a) - MOD_NAMES.indexOf(b));
    return mods.concat([key]).join("+");
}

const KEY_LABELS = {
    "Return": "Return", "space": "Space", "Space": "Space", "Tab": "Tab", "Escape": "Esc", "BackSpace": "Backspace", "Delete": "Delete",
    "Left": "←", "Right": "→", "Up": "↑", "Down": "↓", "Page_Up": "Page Up", "Page_Down": "Page Down", "Home": "Home", "End": "End",
    "Minus": "-", "minus": "-", "Equal": "=", "equal": "=", "Comma": ",", "comma": ",", "Period": ".", "period": ".", "Slash": "/", "slash": "/",
    "BracketLeft": "[", "bracketleft": "[", "BracketRight": "]", "bracketright": "]", "Semicolon": ";", "semicolon": ";", "Apostrophe": "'",
    "apostrophe": "'", "grave": "`", "Grave": "`", "backslash": "\\", "Backslash": "\\", "Print": "Print",
    "WheelScrollUp": "Scroll ↑", "WheelScrollDown": "Scroll ↓", "WheelScrollLeft": "Scroll ←", "WheelScrollRight": "Scroll →",
    "TouchpadScrollUp": "Swipe ↑", "TouchpadScrollDown": "Swipe ↓", "TouchpadScrollLeft": "Swipe ←", "TouchpadScrollRight": "Swipe →",
    "MouseLeft": "Left click", "MouseRight": "Right click", "MouseMiddle": "Middle click", "MouseForward": "Forward button", "MouseBack": "Back button",
    "XF86AudioRaiseVolume": "Volume Up", "XF86AudioLowerVolume": "Volume Down", "XF86AudioMute": "Mute", "XF86AudioMicMute": "Mic Mute",
    "XF86AudioPlay": "Play", "XF86AudioPause": "Pause", "XF86AudioNext": "Next", "XF86AudioPrev": "Previous", "XF86AudioStop": "Stop",
    "XF86MonBrightnessUp": "Brightness Up", "XF86MonBrightnessDown": "Brightness Down", "XF86Launch1": "Launch 1"
};
// "Mod+Shift+Slash" -> ["Super", "Shift", "/"]
function keyCaps(name, modKey) {
    const parts = String(name).split("+");
    const key = parts.pop();
    const caps = parts.map(p => {
        const l = p.toLowerCase();
        if (l === "mod") return modKey || "Super";
        if (l === "win") return "Super";
        if (l === "control") return "Ctrl";
        if (l === "iso_level3_shift" || l === "mod5") return "AltGr";
        return p.charAt(0).toUpperCase() + p.slice(1);
    });
    let label = KEY_LABELS[key];
    if (!label) {
        if (/^XF86/.test(key)) label = key.slice(4).replace(/([a-z])([A-Z0-9])/g, "$1 $2");
        else label = key.length === 1 ? key.toUpperCase() : key.replace(/_/g, " ");
    }
    return caps.concat([label]);
}

const ACTION_TITLES = {
    "toggle-overview": "Overview", "show-hotkey-overlay": "Show important hotkeys", "close-window": "Close window",
    "maximize-column": "Maximize column", "maximize-window-to-edges": "Maximize window", "fullscreen-window": "Full screen",
    "toggle-windowed-fullscreen": "Windowed full screen", "toggle-window-floating": "Float or tile window",
    "switch-focus-between-floating-and-tiling": "Switch between floating and tiled", "toggle-column-tabbed-display": "Tabbed column",
    "quit": "Quit niri", "power-off-monitors": "Turn off displays", "toggle-keyboard-shortcuts-inhibit": "Let apps take shortcuts",
    "screenshot": "Screenshot", "screenshot-screen": "Screenshot of the screen", "screenshot-window": "Screenshot of the window",
    "center-column": "Center column", "center-window": "Center window", "center-visible-columns": "Center visible columns",
    "consume-or-expel-window-left": "Move window into or out of the column on the left",
    "consume-or-expel-window-right": "Move window into or out of the column on the right",
    "expel-window-from-column": "Take window out of its column", "consume-window-into-column": "Pull window into the column",
    "switch-preset-column-width": "Cycle column widths", "switch-preset-window-height": "Cycle window heights",
    "reset-window-height": "Reset window height", "expand-column-to-available-width": "Fill available width",
    "set-dynamic-cast-window": "Share focused window", "set-dynamic-cast-monitor": "Share focused display",
    "clear-dynamic-cast-target": "Stop sharing target", "next-window": "Next window", "previous-window": "Previous window",
    "switch-layout": "Switch keyboard layout", "suspend": "Suspend", "spawn": "Run", "spawn-sh": "Run"
};
const KEY_TITLES = {
    "XF86AudioRaiseVolume": "Volume up", "XF86AudioLowerVolume": "Volume down", "XF86AudioMute": "Mute sound",
    "XF86AudioMicMute": "Mute microphone", "XF86AudioPlay": "Play or pause", "XF86AudioPause": "Play or pause",
    "XF86AudioNext": "Next track", "XF86AudioPrev": "Previous track", "XF86AudioStop": "Stop playing",
    "XF86MonBrightnessUp": "Brightness up", "XF86MonBrightnessDown": "Brightness down"
};
function humanize(s) { const t = String(s).replace(/-/g, " "); return t.charAt(0).toUpperCase() + t.slice(1); }
function stripMarkup(s) { return decode(String(s).replace(/<[^>]*>/g, "")); }
function argText(a) { return typeof a === "string" ? (/\s/.test(a) || a === "" ? JSON.stringify(a) : a) : String(a); }
function base(p) { return String(p).replace(/^.*\//, ""); }

// The action as written, short: "spawn ghostty", "focus-workspace 3".
function actionText(act) {
    if (act.name === "spawn") return [base(act.args[0] || "")].concat(act.args.slice(1).map(argText)).join(" ");
    if (act.name === "spawn-sh") return String(act.args[0] || "");
    const props = Object.keys(act.props || {}).map(k => k + "=" + act.props[k]);
    return [act.name].concat(act.args.map(argText)).concat(props).join(" ");
}
function bindTitle(b) {
    const t = b.props["hotkey-overlay-title"];
    if (typeof t === "string" && t.trim()) return stripMarkup(t).trim();
    const key = String(b.key).split("+");
    if (key.length === 1 && KEY_TITLES[key[0]]) return KEY_TITLES[key[0]];
    const a = b.act;
    if (a.name === "spawn" || a.name === "spawn-sh") return "Run " + actionText(a);
    if (a.name === "focus-workspace") return "Workspace " + a.args.join(" ");
    if (a.name === "next-window" || a.name === "previous-window") {
        const f = a.props.filter === "app-id" ? " of the same app" : "";
        return ACTION_TITLES[a.name] + f;
    }
    const known = ACTION_TITLES[a.name];
    const args = a.args.map(argText).join(" ");
    return (known || humanize(a.name)) + (args ? " " + args : "");
}

const GROUPS = ["Apps & shell", "Windows", "Focus & move", "Sizing", "Workspaces", "Displays", "Screenshots & sharing", "Media keys", "Mouse & scroll", "System", "Other"];
function bindGroup(b) {
    const key = String(b.key).split("+").pop();
    const a = b.act.name;
    if (/^XF86/.test(key)) return "Media keys";
    if (/^(Wheel|Touchpad)Scroll|^Mouse/.test(key)) return "Mouse & scroll";
    if (a === "spawn" || a === "spawn-sh") return "Apps & shell";
    if (/screenshot|dynamic-cast/.test(a)) return "Screenshots & sharing";
    if (/workspace/.test(a)) return "Workspaces";
    if (/monitor/.test(a)) return "Displays";
    if (/width|height|preset|expand-column/.test(a)) return "Sizing";
    if (/^(focus|move|swap)-/.test(a)) return "Focus & move";
    if (/window|column|floating|fullscreen|maximize|tabbed|consume|expel|center/.test(a)) return "Windows";
    if (/^(quit|power-|suspend|show-hotkey|toggle-overview|toggle-keyboard|switch-layout|do-screen|load-config)/.test(a)) return "System";
    return "Other";
}

// shortcuts(nodes, modKey) -> [{id, key, caps, title, detail, group, src, search}]
// binds sections merge: a later bind for the same keys replaces the earlier.
function shortcuts(list, modKey) {
    const seen = {};
    const order = [];
    for (const top of list) {
        let kids = null;
        if (top.name === "binds") kids = top.children;
        else if (top.name === "recent-windows") { const b = (top.children || []).find(c => c.name === "binds"); kids = b ? b.children : null; }
        if (!kids) continue;
        for (const nd of kids) {
            const act = (nd.children || [])[0];
            if (!act) continue;
            const id = keyNorm(nd.name);
            if (seen[id] === undefined) order.push(id);
            seen[id] = { "key": nd.name, "props": nd.props || {}, "act": act, "src": top.src || "" };
        }
    }
    return order.map(id => {
        const b = seen[id];
        const caps = keyCaps(b.key, modKey);
        const title = bindTitle(b);
        const detail = actionText(b.act);
        const group = bindGroup(b);
        return { "id": id, "key": b.key, "caps": caps, "title": title, "detail": detail, "group": group, "src": b.src,
                 "search": (title + " " + detail + " " + caps.join(" ") + " " + b.key + " " + group).toLowerCase() };
    });
}
