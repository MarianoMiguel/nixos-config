pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Common

// Output and input volume through PipeWire. changed(kind) tells the island's
// level display what moved ("volume" or "mic").
//
// The Sound page reads devices, apps and card profiles by key (dev(), stream(),
// card()), so the same page runs on live PipeWire or on a fixture
// (`sound fixture normal|stress|empty|unavailable`, "" for live), where every
// action changes only the fixture. Live volume, mute, balance and default go to
// PipeWire directly; card profiles (wpctl set-profile) and moving an app
// (pw-metadata target.object) go through Sys.run. In the harness nothing is
// written: each change is recorded through Sys.run (`settings dryrun`).
// Profiles are read with pw-dump while the page is open (`watching`).
Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    // The defaults always (island, bar); every device and app while the page is open.
    PwObjectTracker { objects: [root.sink, root.source].concat(root.watching ? root.outputs.concat(root.inputs, root.streams) : []).filter(n => n) }

    readonly property real volume: fake ? dev(defaultOutput).volume : (sink && sink.audio ? level(sink) : 0)
    readonly property bool muted: fake ? dev(defaultOutput).muted : (sink && sink.audio ? sink.audio.muted : false)
    readonly property bool micMuted: fake ? dev(defaultInput).muted : (source && source.audio ? source.audio.muted : false)
    readonly property string device: fake ? dev(defaultOutput).title : (sink ? (sink.description || sink.nickname || sink.name || "") : "")
    readonly property var outputs: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var inputs: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)
    readonly property var streams: Pipewire.nodes.values.filter(n => n.audio && n.isStream && cls(n) === "Stream/Output/Audio")

    signal changed(string kind)

    // The island, the sidebar and the keybinds. Above 100% only with over-amplification.
    function setVolume(v) { setDeviceVolume(defaultOutput, v); changed("volume"); }
    function step(delta) { setVolume(Math.round((volume + delta) * 100) / 100); }
    function toggleMute() { setDeviceMuted(defaultOutput, !muted); changed("volume"); }
    function toggleMic() { setDeviceMuted(defaultInput, !micMuted); changed("mic"); }
    function useOutput(node) { if (node) setDefault("n" + node.id); }

    // ------------------------------------------------------------ state

    property string fixture: ""
    property var fx: null
    readonly property bool fake: fixture !== "" && fx !== null
    // The Sound page sets this while it is open: track every node, read
    // profiles, run the input meter.
    property bool watching: false
    // Which inline chooser is open on the page: "profile:output",
    // "profile:input", "move:<stream key>". Here so IPC can open them.
    property string openPanel: ""
    // A section of the page to bring into view (output, input, apps, sounds);
    // the page scrolls to it and clears it.
    property string reveal: ""
    // In the harness the live meter reads the real microphone only when asked
    // (`sound meter true`): its capture stream shows in the live privacy dot.
    property bool meterInHarness: false

    readonly property bool available: fake ? fx.available : Pipewire.ready
    readonly property bool overAmplify: pref("sound.overamplify") === true
    readonly property real maxVolume: overAmplify ? 1.5 : 1
    readonly property bool sounds: pref("sounds") === true

    readonly property var nodeMap: {
        const m = {};
        for (const n of Pipewire.nodes.values) m["n" + n.id] = n;
        return m;
    }
    readonly property string defaultOutput: fake ? fx.defaultOutput : (sink ? "n" + sink.id : "")
    readonly property string defaultInput: fake ? fx.defaultInput : (source ? "n" + source.id : "")
    readonly property var outputKeys: fake ? fx.outputs.map(d => d.key) : sorted(outputs).map(n => "n" + n.id)
    readonly property var inputKeys: fake ? fx.inputs.map(d => d.key) : sorted(inputs).map(n => "n" + n.id)
    readonly property var streamKeys: fake ? fx.streams.map(s => s.key) : streams.slice().sort((a, b) => a.id - b.id).map(n => "n" + n.id)
    // Sound cards whose profile is off but could be on (an HDMI port after
    // undocking, a headset someone switched off).
    readonly property var offCards: (fake ? fx.cards : Object.values(liveCards)).filter(c => {
        const cur = c.profiles.find(p => p.index === c.current);
        return (!cur || cur.name === "off") && !!bestProfile(c);
    }).map(c => c.key)

    // ------------------------------------------------------------ reading

    function cls(n) { return (n.properties && n.properties["media.class"]) || ""; }
    function side(ch) { const s = PwAudioChannel.toString(ch); return /Left/.test(s) ? -1 : /Right/.test(s) ? 1 : 0; }
    function list(l) { return l ? Array.prototype.slice.call(l) : []; }
    function level(n) { const v = list(n.audio.volumes); return v.length ? Math.max.apply(null, v) : n.audio.volume; }

    function kindOf(n, p) {
        const s = [n.name, n.description, p["device.profile.description"], p["device.form-factor"]].join(" ");
        if (p["device.api"] === "bluez5" || /^bluez/.test(n.name || "")) return "bluetooth";
        if (/hdmi|displayport/i.test(s)) return "hdmi";
        if (/headphone|headset/i.test(s)) return "headphones";
        if (p["device.bus"] === "usb" || /^alsa_(input|output)\.usb/.test(n.name || "")) return "usb";
        return n.isSink ? "speaker" : "mic";
    }
    function kindLabel(kind) {
        return ({ "speaker": "Built-in", "mic": "Built-in", "headphones": "Headphones", "hdmi": "HDMI / DisplayPort", "bluetooth": "Bluetooth", "usb": "USB" })[kind] || "";
    }
    function kindIcon(kind, output) {
        return ({ "speaker": "speaker", "mic": "mic", "headphones": "headphones", "hdmi": "display", "bluetooth": "bluetooth", "usb": output ? "usb" : "mic" })[kind] || (output ? "speaker" : "mic");
    }
    function rank(kind) { return ["speaker", "mic", "headphones", "hdmi", "usb", "bluetooth"].indexOf(kind); }
    function sorted(nodes) {
        return nodes.slice().sort((a, b) => {
            const ka = kindOf(a, a.properties || {}), kb = kindOf(b, b.properties || {});
            return (rank(ka) - rank(kb)) || (a.description || a.name || "").localeCompare(b.description || b.name || "") || a.id - b.id;
        });
    }

    // Balance from per-channel volumes: -1 all left, 0 even, 1 all right.
    function balanceOf(vols, sides) {
        let l = -1, r = -1;
        for (let i = 0; i < vols.length; i++) {
            if (sides[i] < 0) l = Math.max(l, vols[i]);
            else if (sides[i] > 0) r = Math.max(r, vols[i]);
        }
        if (l < 0 || r < 0) return { "stereo": false, "b": 0 };
        if (l === r || Math.max(l, r) <= 0) return { "stereo": true, "b": 0 };
        return { "stereo": true, "b": r < l ? -(1 - r / l) : 1 - l / r };
    }
    function spread(sides, m, b) {
        return sides.map(s => s < 0 ? m * (b > 0 ? 1 - b : 1) : s > 0 ? m * (b < 0 ? 1 + b : 1) : m);
    }

    function blankDev() {
        return { "ok": false, "key": "", "title": "", "subtitle": "", "kind": "", "icon": "speaker", "volume": 0, "muted": false,
                 "balance": 0, "hasBalance": false, "card": "", "isDefault": false, "output": true };
    }
    function dev(key) {
        if (!key) return blankDev();
        if (fake) {
            let d = fx.outputs.find(x => x.key === key);
            const output = !!d;
            if (!d) d = fx.inputs.find(x => x.key === key);
            if (!d) return blankDev();
            const c = fx.cards.find(x => x.key === d.card);
            return { "ok": true, "key": key, "title": d.title, "subtitle": d.sub || [kindLabel(d.kind), c ? c.title : ""].filter(s => s).join(" · "),
                     "kind": d.kind, "icon": kindIcon(d.kind, output), "volume": d.volume, "muted": d.muted, "balance": d.balance || 0,
                     "hasBalance": output && d.stereo !== false, "card": d.card || "",
                     "isDefault": key === (output ? fx.defaultOutput : fx.defaultInput), "output": output };
        }
        const n = nodeMap[key];
        if (!n) return blankDev();
        const p = n.properties || {};
        const kind = kindOf(n, p);
        // "Ryzen HD Audio Controller Speaker" → "Speaker", from "Ryzen HD Audio Controller".
        const desc = n.description || n.nickname || n.name || "";
        const prof = p["device.profile.description"] || "";
        let title = desc, from = "";
        if (prof && desc.length > prof.length && desc.endsWith(prof)) { title = prof; from = desc.slice(0, desc.length - prof.length).trim(); }
        const c = liveCards["c" + p["device.id"]];
        if (!from && c && c.title !== title) from = c.title;
        const codec = p["api.bluez5.codec"] ? String(p["api.bluez5.codec"]).toUpperCase().replace(/_/g, "-") : "";
        const a = n.audio;
        const vols = a ? list(a.volumes) : [];
        const bal = balanceOf(vols, a ? list(a.channels).map(side) : []);
        return { "ok": true, "key": key, "title": title, "subtitle": [kindLabel(kind), kind === "bluetooth" ? codec : from].filter(s => s).join(" · "),
                 "kind": kind, "icon": kindIcon(kind, n.isSink), "volume": vols.length ? Math.max.apply(null, vols) : (a ? a.volume : 0),
                 "muted": a ? a.muted : false, "balance": bal.b, "hasBalance": n.isSink && bal.stereo,
                 "card": p["device.id"] !== undefined ? "c" + p["device.id"] : "",
                 "isDefault": n.isSink ? (!!sink && sink.id === n.id) : (!!source && source.id === n.id), "output": n.isSink };
    }

    function blankStream() { return { "ok": false, "key": "", "app": "", "title": "", "icon": "", "volume": 0, "muted": false, "target": "" }; }
    function stream(key) {
        if (!key) return blankStream();
        if (fake) {
            const s = fx.streams.find(x => x.key === key);
            return s ? Object.assign({ "ok": true }, s) : blankStream();
        }
        const n = nodeMap[key];
        if (!n) return blankStream();
        const p = n.properties || {};
        const app = p["application.name"] || n.description || n.nickname || n.name || "App";
        const title = p["media.name"] || "";
        const g = Pipewire.linkGroups.values.find(g => g.source && g.source.id === n.id && g.target && !g.target.isStream);
        return { "ok": true, "key": key, "app": app, "title": title === app ? "" : title,
                 "icon": p["application.icon-name"] || p["pipewire.access.portal.app_id"] || p["application.id"] || p["application.process.binary"] || "",
                 "volume": n.audio ? n.audio.volume : 0, "muted": n.audio ? n.audio.muted : false, "target": g ? "n" + g.target.id : "" };
    }

    // A sound card: {key, id, title, api, profiles: [{index, name, title, available, priority}], current}.
    function card(key) {
        if (!key) return null;
        if (fake) return fx.cards.find(c => c.key === key) || null;
        return liveCards[key] || null;
    }
    // What a profile means, in a few words, where the name says it.
    function profileHint(p) {
        const n = p.name || "";
        if (!p.available) return "Not plugged in";
        if (n === "off") return "The device stays silent and unused";
        if (/^a2dp/.test(n)) return "Best sound, no microphone";
        if (/^headset|hfp|hsp/.test(n)) return "Microphone on, phone-call sound";
        if (n === "pro-audio") return "Every channel, no mixing";
        return "";
    }
    function bestProfile(c) {
        const usable = c.profiles.filter(p => p.available && p.name !== "off" && p.name !== "pro-audio");
        return usable.sort((a, b) => (b.priority || 0) - (a.priority || 0))[0] || null;
    }

    // ------------------------------------------------------------ profiles (pw-dump)

    property var liveCards: ({})
    function parseDump(text) {
        const out = {};
        for (const o of JSON.parse(text)) {
            if (!/Device$/.test(o.type || "")) continue;
            const info = o.info || {};
            const p = info.props || {};
            if (p["media.class"] !== "Audio/Device") continue;
            const params = info.params || {};
            const cur = (params.Profile || [])[0];
            out["c" + o.id] = {
                "key": "c" + o.id, "id": o.id, "title": p["device.description"] || p["device.nick"] || p["device.name"] || "Sound card",
                "api": p["device.api"] || "", "bus": p["device.bus"] || "",
                "profiles": (params.EnumProfile || []).map(x => ({ "index": x.index, "name": x.name || "", "title": x.description || x.name || "",
                                                                  "available": x.available !== "no", "priority": x.priority || 0 })),
                "current": cur ? cur.index : -1
            };
        }
        return out;
    }
    Process {
        id: dump
        command: ["pw-dump"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.liveCards = root.parseDump(text); } catch (e) { console.warn("Audio: unreadable pw-dump", e); } }
        }
    }
    Timer { id: dumpSoon; interval: 400; onTriggered: if (root.watching && !root.fake && !dump.running) dump.running = true }
    readonly property int nodeCount: Pipewire.nodes.values.length
    onNodeCountChanged: dumpSoon.restart()
    onWatchingChanged: { if (watching) dumpSoon.restart(); else openPanel = ""; }

    // ------------------------------------------------------------ input meter

    // The default input's peak, on a 54 dB scale so speech fills the middle.
    PwNodePeakMonitor {
        id: peak
        node: root.source
        enabled: root.watching && !root.fake && !!root.source && (!Sys.harness || root.meterInHarness)
    }
    property real fakeLevel: 0
    property int fakeTick: 0
    readonly property real inputLevel: {
        if (fake) return fakeLevel;
        if (!peak.enabled || peak.peak <= 0.002) return 0;
        return Math.max(0, Math.min(1, (20 * Math.log10(peak.peak) + 54) / 54));
    }
    // A fixture "speaks": bursts and pauses; louder in stress.
    Timer {
        interval: 70; repeat: true
        running: root.fake && root.watching && root.defaultInput !== "" && !root.dev(root.defaultInput).muted
        onRunningChanged: if (!running) root.fakeLevel = 0
        onTriggered: {
            const t = ++root.fakeTick;
            const speaking = Math.floor(t / 22) % 3 !== 2;
            const loud = root.fixture === "stress" ? 1.3 : 1;
            const target = speaking ? Math.min(1, (0.38 + 0.4 * Math.random() * Math.abs(Math.sin(t / 2.6))) * loud) : 0.04 * Math.random();
            root.fakeLevel = root.fakeLevel * 0.45 + target * 0.55;
        }
    }

    // ------------------------------------------------------------ writing

    // Live: apply to PipeWire. Harness: record the equivalent command instead
    // (sliders coalesce, so a drag records its last value).
    property var pending: ({})
    function write(tag, cmd, apply) {
        if (!Sys.harness) { apply(); return; }
        const p = Object.assign({}, pending);
        p[tag] = cmd;
        pending = p;
        flush.restart();
    }
    Timer {
        id: flush; interval: 300
        onTriggered: { const p = root.pending; root.pending = {}; for (const k in p) Sys.run(p[k]); }
    }
    function patch(listName, key, change) {
        const f = Object.assign({}, fx);
        f[listName] = f[listName].map(x => x.key === key ? Object.assign({}, x, change) : x);
        fx = f;
    }
    function fakeList(key) { return fx.outputs.some(d => d.key === key) ? "outputs" : "inputs"; }
    // Over-amplification is for what plays (outputs, apps); inputs stop at 100%.
    function clamp(v, top) { return Math.max(0, Math.min(top || maxVolume, Math.round(v * 100) / 100)); }

    function setDefault(key) {
        if (!key) return;
        if (fake) {
            const f = Object.assign({}, fx);
            if (fakeList(key) === "outputs") f.defaultOutput = key; else f.defaultInput = key;
            fx = f;
            return;
        }
        const n = nodeMap[key];
        if (!n) return;
        write("default" + n.isSink, ["wpctl", "set-default", String(n.id)], () => {
            if (n.isSink) Pipewire.preferredDefaultAudioSink = n; else Pipewire.preferredDefaultAudioSource = n;
        });
    }
    // Moving a level unmutes, as the volume keys do.
    function setDeviceVolume(key, v) {
        if (!key) return;
        const isInput = fake ? fakeList(key) === "inputs" : !!nodeMap[key] && !nodeMap[key].isSink;
        v = clamp(v, isInput ? 1 : maxVolume);
        if (fake) { patch(fakeList(key), key, { "volume": v, "muted": false }); return; }
        const n = nodeMap[key];
        if (!n || !n.audio) return;
        const d = dev(key);
        write(key + ":volume", ["wpctl", "set-volume", String(n.id), v.toFixed(2)], () => {
            if (n.audio.muted) n.audio.muted = false;
            if (d.hasBalance) n.audio.volumes = spread(list(n.audio.channels).map(side), v, d.balance);
            else n.audio.volume = v;
        });
    }
    function setDeviceMuted(key, m) {
        if (!key) return;
        if (fake) { patch(fakeList(key), key, { "muted": m }); return; }
        const n = nodeMap[key];
        if (!n || !n.audio) return;
        write(key + ":mute", ["wpctl", "set-mute", String(n.id), m ? "1" : "0"], () => { n.audio.muted = m; });
    }
    function setBalance(key, b) {
        b = Math.max(-1, Math.min(1, Math.round(b * 100) / 100));
        if (fake) { patch("outputs", key, { "balance": b }); return; }
        const n = nodeMap[key];
        if (!n || !n.audio) return;
        const sides = list(n.audio.channels).map(side);
        const vols = spread(sides, dev(key).volume, b);
        write(key + ":balance", ["pw-cli", "set-param", String(n.id), "Props", JSON.stringify({ "channelVolumes": vols.map(v => Math.pow(v, 3)) })],
              () => { n.audio.volumes = vols; });
    }
    function setStreamVolume(key, v) {
        v = clamp(v);
        if (fake) { patch("streams", key, { "volume": v, "muted": false }); return; }
        const n = nodeMap[key];
        if (!n || !n.audio) return;
        write(key + ":volume", ["wpctl", "set-volume", String(n.id), v.toFixed(2)], () => {
            if (n.audio.muted) n.audio.muted = false;
            n.audio.volume = v;
        });
    }
    function setStreamMuted(key, m) {
        if (fake) { patch("streams", key, { "muted": m }); return; }
        const n = nodeMap[key];
        if (!n || !n.audio) return;
        write(key + ":mute", ["wpctl", "set-mute", String(n.id), m ? "1" : "0"], () => { n.audio.muted = m; });
    }
    // WirePlumber moves a stream that has a target.object in the default metadata.
    function moveStream(key, outKey) {
        if (fake) { patch("streams", key, { "target": outKey }); return; }
        const n = nodeMap[key], o = nodeMap[outKey];
        if (!n || !o) return;
        Sys.run(["pw-metadata", String(n.id), "target.object", o.name]);
    }
    // Switches at once; the toast's Undo puts the old profile back.
    function setProfile(cardKey, index, quiet) {
        const c = card(cardKey);
        const p = c ? c.profiles.find(x => x.index === index) : null;
        if (!p || !p.available || c.current === index) return;
        const prev = c.current;
        if (fake) {
            const f = Object.assign({}, fx);
            f.cards = f.cards.map(x => x.key === cardKey ? Object.assign({}, x, { "current": index }) : x);
            fx = f;
        } else {
            Sys.run(["wpctl", "set-profile", String(c.id), String(index)]);
            dumpSoon.restart();
        }
        if (!quiet) Toasts.undo(c.title + ": " + p.title, null, () => root.setProfile(cardKey, prev, true), "speaker");
    }
    function turnOn(cardKey) {
        const c = card(cardKey);
        const p = c ? bestProfile(c) : null;
        if (p) setProfile(cardKey, p.index);
    }

    // Folio settings; a fixture keeps its own, and the harness never writes
    // the real settings file.
    property var harnessPrefs: ({})
    function pref(k) {
        if (fake) return fx.prefs[k];
        if (Sys.harness && k in harnessPrefs) return harnessPrefs[k];
        return Settings.get(k);
    }
    function setPref(k, v) {
        if (fake) { const f = Object.assign({}, fx); f.prefs = Object.assign({}, f.prefs); f.prefs[k] = v; fx = f; }
        else if (Sys.harness) { const h = Object.assign({}, harnessPrefs); h[k] = v; harnessPrefs = h; console.warn("dry-run: Settings.set", k, v); }
        else Settings.set(k, v);
    }
    // Turning over-amplification off brings anything above 100% back to it.
    function setOverAmplify(on) {
        setPref("sound.overamplify", on);
        if (on) return;
        for (const k of outputKeys) if (dev(k).volume > 1) setDeviceVolume(k, 1);
        for (const k of streamKeys) if (stream(k).volume > 1) setStreamVolume(k, 1);
    }
    function setSounds(on) { setPref("sounds", on); }

    // ------------------------------------------------------------ fixtures

    function setFixture(name) {
        openPanel = "";
        fx = name ? makeFixture(name) : null;
        fixture = name || "";
    }
    function makeFixture(name) {
        const none = { "available": true, "prefs": { "sound.overamplify": false, "sounds": false }, "outputs": [], "inputs": [], "streams": [],
                       "cards": [], "defaultOutput": "", "defaultInput": "" };
        if (name === "unavailable") return Object.assign({}, none, { "available": false });
        if (name === "empty") return none;
        if (name === "stress") return stressFixture();
        return normalFixture();
    }
    function profiles(rows) { return rows.map((r, i) => ({ "index": i, "name": r[0], "title": r[1], "available": r[2] !== false, "priority": r[3] || 0 })); }
    function normalFixture() {
        return {
            "available": true,
            "prefs": { "sound.overamplify": false, "sounds": true },
            "cards": [
                { "key": "c1", "id": 42, "title": "Ryzen HD Audio Controller", "api": "alsa", "current": 2, "profiles": profiles([
                    ["off", "Off"], ["HiFi (Headphones, Mic1, Mic2)", "Play HiFi quality Music (Headphones, Mic1, Mic2)", false, 8500],
                    ["HiFi (Mic1, Mic2, Speaker)", "Play HiFi quality Music (Mic1, Mic2, Speaker)", true, 8400], ["pro-audio", "Pro Audio", true, 1]]) },
                { "key": "c2", "id": 67, "title": "Radeon High Definition Audio Controller", "api": "alsa", "current": 1, "profiles": profiles([
                    ["off", "Off"], ["HiFi", "Play HiFi quality Music", true, 13000], ["pro-audio", "Pro Audio", true, 1]]) },
                { "key": "c3", "id": 90, "title": "WH-1000XM4", "api": "bluez5", "current": 2, "profiles": profiles([
                    ["off", "Off"], ["a2dp-sink-sbc_xq", "High Fidelity Playback (A2DP Sink, codec SBC-XQ)", true, 17],
                    ["a2dp-sink", "High Fidelity Playback (A2DP Sink, codec AAC)", true, 18],
                    ["headset-head-unit", "Headset Head Unit (HSP/HFP, codec mSBC)", true, 2]]) },
                { "key": "c4", "id": 95, "title": "Shure MV7", "api": "alsa", "bus": "usb", "current": 1, "profiles": profiles([
                    ["off", "Off"], ["input:mono-fallback", "Mono Input", true, 51], ["pro-audio", "Pro Audio", true, 1]]) },
                { "key": "c5", "id": 99, "title": "Dock Audio", "api": "alsa", "bus": "usb", "current": 0, "profiles": profiles([
                    ["off", "Off"], ["output:analog-stereo+input:mono-fallback", "Analog Stereo Output + Mono Input", true, 6501],
                    ["output:iec958-stereo", "Digital Stereo (IEC958) Output", true, 5500]]) }
            ],
            "outputs": [
                { "key": "o1", "title": "Speaker", "kind": "speaker", "card": "c1", "volume": 0.46, "muted": false, "balance": 0 },
                { "key": "o2", "title": "LG HDR 4K", "kind": "hdmi", "card": "c2", "volume": 0.8, "muted": false, "balance": 0 },
                { "key": "o3", "title": "WH-1000XM4", "sub": "Bluetooth · AAC", "kind": "bluetooth", "card": "c3", "volume": 0.62, "muted": false, "balance": -0.2 }
            ],
            "inputs": [
                { "key": "i1", "title": "Digital Microphone", "kind": "mic", "card": "c1", "volume": 0.85, "muted": false },
                { "key": "i2", "title": "Stereo Microphone", "kind": "mic", "card": "c1", "volume": 1, "muted": false },
                { "key": "i3", "title": "Shure MV7", "sub": "USB", "kind": "usb", "card": "c4", "volume": 0.7, "muted": false }
            ],
            "defaultOutput": "o1", "defaultInput": "i1",
            "streams": [
                { "key": "s1", "app": "Spotify", "title": "Almost Blue · Chet Baker", "icon": "spotify", "volume": 0.8, "muted": false, "target": "o1" },
                { "key": "s2", "app": "Google Chrome", "title": "Tiny Desk Concert · YouTube", "icon": "google-chrome", "volume": 1, "muted": false, "target": "o1" },
                { "key": "s3", "app": "Slack", "title": "Huddle in #design", "icon": "slack", "volume": 0.55, "muted": true, "target": "o3" }
            ]
        };
    }
    function stressFixture() {
        const long = s => (s + " ").repeat(8).slice(0, 90).trim();
        const kinds = ["speaker", "headphones", "hdmi", "hdmi", "usb", "bluetooth", "bluetooth", "hdmi", "usb", "bluetooth", "speaker", "hdmi"];
        const cards = [{ "key": "c1", "id": 1, "title": long("Ryzen HD Audio Controller with a very long card description"), "api": "alsa", "current": 3,
                         "profiles": profiles([["off", "Off"]].concat(Array.from({ length: 8 }, (_, i) =>
                             ["HiFi " + i, long("Play HiFi quality Music (Headphones, Mic1, Mic2, Speaker, HDMI " + (i + 1) + ")"), i !== 2, 9000 - i]))) },
                       { "key": "c2", "id": 2, "title": long("Off card with a long name that should elide"), "api": "alsa", "current": 0,
                         "profiles": profiles([["off", "Off"], ["output:analog-stereo", "Analog Stereo Output", true, 6500]]) }];
        return {
            "available": true,
            "prefs": { "sound.overamplify": true, "sounds": false },
            "cards": cards,
            "outputs": kinds.map((k, i) => ({ "key": "o" + i, "title": long("Output device " + (i + 1) + " " + k + " with a ninety character name"),
                                              "kind": k, "card": "c1", "volume": i === 0 ? 1.38 : (i * 0.083) % 1.5, "muted": i % 4 === 3, "balance": i === 0 ? -0.4 : 0 })),
            "inputs": Array.from({ length: 9 }, (_, i) => ({ "key": "i" + i, "title": long("Input device " + (i + 1) + " microphone with a ninety character name"),
                                                             "kind": ["mic", "usb", "bluetooth", "headphones"][i % 4], "card": "c1", "volume": 0.3 + i * 0.07, "muted": i === 4 })),
            "defaultOutput": "o0", "defaultInput": "i0",
            "streams": Array.from({ length: 16 }, (_, i) => ({ "key": "s" + i, "app": long(["Spotify", "Google Chrome", "Slack", "Firefox", "Code", "mpv"][i % 6] + " app " + (i + 1)),
                                                              "title": long("Media title number " + (i + 1) + " that runs on and on"),
                                                              "icon": ["spotify", "google-chrome", "slack", "firefox", "code", "mpv", "", "nonexistent-app"][i % 8],
                                                              "volume": i === 0 ? 1.5 : (0.2 + i * 0.05) % 1.2, "muted": i % 5 === 4, "target": "o" + (i % 12) }))
        };
    }

    // A compact picture of what the page shows, for tests.
    function snapshot() {
        const d = k => { const x = dev(k); return { "key": k, "title": x.title, "sub": x.subtitle, "vol": Math.round(x.volume * 100), "muted": x.muted, "default": x.isDefault, "balance": x.balance, "card": x.card }; };
        return {
            "fixture": fixture, "available": available, "overAmplify": overAmplify, "sounds": sounds, "level": Math.round(inputLevel * 100) / 100,
            "outputs": outputKeys.map(d), "inputs": inputKeys.map(d),
            "streams": streamKeys.map(k => { const s = stream(k); return { "key": k, "app": s.app, "title": s.title, "vol": Math.round(s.volume * 100), "muted": s.muted, "target": s.target }; }),
            "cards": (fake ? fx.cards : Object.values(liveCards)).map(c => ({ "key": c.key, "title": c.title, "current": c.current, "profiles": c.profiles.map(p => p.index + ":" + p.name + (p.available ? "" : " (n/a)")) })),
            "offCards": offCards, "openPanel": openPanel
        };
    }

    IpcHandler {
        target: "sound"
        // normal | stress | empty | unavailable; "" for live PipeWire.
        function fixture(name: string): void { root.setFixture(name); }
        function state(): string { return JSON.stringify(root.snapshot(), null, 1); }
        // Make the index-th output or input (as the page lists them) the default.
        function use(kind: string, index: int): void { const k = (kind === "input" ? root.inputKeys : root.outputKeys)[index]; if (k) root.setDefault(k); }
        // what: output | input | app:N (N as the page lists apps).
        function volume(what: string, value: real): void {
            if (what.indexOf("app:") === 0) root.setStreamVolume(root.streamKeys[+what.slice(4)], value);
            else root.setDeviceVolume(what === "input" ? root.defaultInput : root.defaultOutput, value);
        }
        function mute(what: string): void {
            if (what.indexOf("app:") === 0) { const k = root.streamKeys[+what.slice(4)]; root.setStreamMuted(k, !root.stream(k).muted); }
            else { const k = what === "input" ? root.defaultInput : root.defaultOutput; root.setDeviceMuted(k, !root.dev(k).muted); }
        }
        function balance(value: real): void { root.setBalance(root.defaultOutput, value); }
        function move(app: int, output: int): void { root.moveStream(root.streamKeys[app], root.outputKeys[output]); }
        // card: output | input (the default device's card) or a card key; index: PipeWire's profile index.
        function profile(card: string, index: int): void {
            const k = card === "output" ? root.dev(root.defaultOutput).card : card === "input" ? root.dev(root.defaultInput).card : card;
            root.setProfile(k, index);
        }
        function turnOn(card: string): void { root.turnOn(card); }
        // profile:output | profile:input | move:N | "" to close.
        function open(panel: string): void { root.openPanel = panel.indexOf("move:") === 0 ? "move:" + (root.streamKeys[+panel.slice(5)] || "") : panel; }
        function overamplify(on: bool): void { root.setOverAmplify(on); }
        function sounds(on: bool): void { root.setSounds(on); }
        // Open Settings at a section of the Sound page: output | input | apps | sounds.
        function section(name: string): void {
            if (!Shell.settingsOpen || Shell.settingsPage !== "sound") Shell.openSettings("sound");
            root.reveal = name || "output";
        }
        // Harness: let the live meter read the real default microphone (read only).
        function meter(on: bool): void { root.meterInHarness = on; }
    }
}
