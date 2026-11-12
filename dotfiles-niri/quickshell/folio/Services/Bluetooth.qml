pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

// Bluetooth through BlueZ: Quickshell's Bluetooth module for state, power,
// discovery, connecting and forgetting; `bluetoothctl` for pairing, because
// pairing may need an agent to show or confirm a passkey (Quickshell has no
// agent). Every write is skipped in the harness (recorded with Sys.run as the
// bluetoothctl command it stands for).
//
// Fixtures (IPC `bluetooth fixture normal|stress|empty|off|unavailable`, ""
// for live) stand in for BlueZ; actions then change the fixture only.
Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: fake ? fx.available : adapter !== null
    readonly property bool on: fake ? fx.on : (adapter ? adapter.enabled : false)
    readonly property bool blocked: fake ? !!fx.blocked : (adapter ? adapter.state === BluetoothAdapterState.Blocked : false)
    readonly property bool switching: !fake && !!adapter && (adapter.state === BluetoothAdapterState.Enabling || adapter.state === BluetoothAdapterState.Disabling)
    readonly property string name: fake ? fx.name : (adapter ? adapter.name : "")
    readonly property bool discovering: fake ? !!fx.discovering : (adapter ? adapter.discovering : false)
    // BlueZ's devices (fixture ones answer connect()/disconnect() too).
    readonly property var devices: fake ? fxDevices : (adapter && adapter.devices ? adapter.devices.values : [])
    readonly property var connected: devices.filter(d => d.connected)
    readonly property string summary: connected.length === 0 ? (on ? "On" : "Off") : connected.length === 1 ? (connected[0].name || connected[0].deviceName || "Connected") : connected.length + " devices"
    // The same devices, described for pages: [{address, name, unnamed, glyph, kind, paired, connected, busy, battery, ref}].
    readonly property var items: devices.map(d => describe(d))

    property var forgetting: ({})       // address → true while its undo toast is up
    property var pairing: null          // {address, name, glyph, step: working|confirm|display|pin|connecting|failed, passkey, text}
    property var pending: ({})          // address → "connect" | "disconnect" while this shell waits on it

    property string fixture: ""
    readonly property bool fake: fixture !== ""
    property var fx: ({})
    readonly property var fxDevices: fake ? (fx.devices || []).map(d => Object.assign({}, d, {
        "connect": () => root.connectDevice(d.address), "disconnect": () => root.disconnectDevice(d.address) })) : []

    // A device connecting or going away has a sound (Sounds device-in,
    // device-out), judged once the change settles. The first look (BlueZ
    // fills in after start) and a switch to or from a fixture only note what
    // is connected.
    readonly property var linked: connected.map(d => d.address)
    property var heard: null
    property string heardFixture: ""
    Timer { running: true; interval: 4000; onTriggered: { root.heard = root.linked; root.heardFixture = root.fixture; } }
    onLinkedChanged: Qt.callLater(root.listen)
    function listen() {
        if (heard === null) return;
        if (heardFixture === fixture && linked.some(a => heard.indexOf(a) < 0)) Sounds.play("device-in");
        else if (heardFixture === fixture && heard.some(a => linked.indexOf(a) < 0)) Sounds.play("device-out");
        heard = linked;
        heardFixture = fixture;
    }

    // ---------------------------------------------------------- describing

    function describe(d) {
        const name = d.name || d.deviceName || "";
        const k = kindOf(d.icon || "", name);
        const st = d.state;
        const p = pending[d.address] || "";
        return {
            "address": d.address, "name": name || d.address, "unnamed": !name || /^([0-9A-F]{2}[-:]){5}[0-9A-F]{2}$/i.test(name),
            "glyph": k[0], "kind": k[1], "paired": !!(d.paired || d.bonded), "connected": !!d.connected, "trusted": !!d.trusted,
            "connecting": st === BluetoothDeviceState.Connecting || p === "connect",
            "busy": st === BluetoothDeviceState.Connecting || st === BluetoothDeviceState.Disconnecting || !!d.pairing || p !== "",
            "battery": d.batteryAvailable ? d.battery : -1, "ref": d
        };
    }
    // BlueZ's icon name (or, without one, the device's name) → [glyph, kind].
    function kindOf(icon, name) {
        const by = {
            "audio-headset": ["headphones", "Headset"], "audio-headphones": ["headphones", "Headphones"], "audio-card": ["speaker", "Speaker"],
            "input-mouse": ["mouse", "Mouse"], "input-keyboard": ["keyboard", "Keyboard"], "input-gaming": ["gamepad", "Game controller"],
            "input-tablet": ["pencil", "Tablet"], "phone": ["phone", "Phone"], "computer": ["laptop", "Computer"], "video-display": ["display", "Display"],
            "camera-photo": ["camera", "Camera"], "camera-video": ["camera", "Camera"], "printer": ["printer", "Printer"], "multimedia-player": ["music", "Player"],
            "modem": ["globe", "Modem"], "network-wireless": ["wifi", "Access point"], "scanner": ["printer", "Scanner"]
        };
        if (by[icon]) return by[icon];
        const n = name.toLowerCase();
        if (/airpods|buds|headphone|headset|wh-1000|wf-1000|earbud|beats/.test(n)) return ["headphones", "Headphones"];
        if (/mouse|mx master|mx anywhere|trackball|magic trackpad/.test(n)) return ["mouse", "Mouse"];
        if (/keyboard|mx keys|keychron|magic keyboard/.test(n)) return ["keyboard", "Keyboard"];
        if (/iphone|pixel|galaxy s|android|phone/.test(n)) return ["phone", "Phone"];
        if (/controller|gamepad|dualsense|dualshock|joy-con/.test(n)) return ["gamepad", "Game controller"];
        if (/watch/.test(n)) return ["watch", "Watch"];
        if (/speaker|soundbar|jbl|boom|sonos/.test(n)) return ["speaker", "Speaker"];
        return ["bluetooth", "Device"];
    }
    function find(address) { return devices.find(d => d.address === address) || null; }

    // ------------------------------------------------------------- actions

    // Runs fn against BlueZ, or records the bluetoothctl command it stands for in the harness.
    function act(cmd, fn) { if (Sys.harness) { Sys.run(cmd); return false; } fn(); return true; }

    function setOn(v) {
        if (fake) {
            patch(f => { f.on = v; f.discovering = false; if (!v) f.devices.forEach(d => { d.connected = false; d.state = BluetoothDeviceState.Disconnected; }); });
            return;
        }
        if (adapter) act(["bluetoothctl", "power", v ? "on" : "off"], () => adapter.enabled = v);
    }
    function setDiscovering(v) {
        if (fake) { if (fx.on) patch(f => f.discovering = v); return; }
        if (adapter && adapter.enabled && adapter.discovering !== v) act(["bluetoothctl", "scan", v ? "on" : "off"], () => adapter.discovering = v);
    }
    function toggle(item) { if (item.connected) disconnectDevice(item.address); else connectDevice(item.address); }

    function connectDevice(address) {
        if (fake) {
            patch(f => f.devices.forEach(d => { if (d.address === address) d.state = BluetoothDeviceState.Connecting; }));
            later(1300, () => {
                const failing = (fx.failing || {})[address];
                patch(f => f.devices.forEach(d => { if (d.address === address) { d.state = failing ? BluetoothDeviceState.Disconnected : BluetoothDeviceState.Connected; d.connected = !failing; } }));
                if (failing) root.couldNot(address);
            });
            return;
        }
        const d = find(address);
        if (!d) return;
        if (act(["bluetoothctl", "connect", address], () => d.connect())) {
            setPending(address, "connect");
            watches = watches.concat([{ "address": address, "since": Date.now(), "seen": false }]);
        }
    }
    function disconnectDevice(address) {
        if (fake) {
            patch(f => f.devices.forEach(d => { if (d.address === address) d.state = BluetoothDeviceState.Disconnecting; }));
            later(700, () => patch(f => f.devices.forEach(d => { if (d.address === address) { d.state = BluetoothDeviceState.Disconnected; d.connected = false; } })));
            return;
        }
        const d = find(address);
        if (d) act(["bluetoothctl", "disconnect", address], () => d.disconnect());
    }
    function couldNot(address) {
        const d = find(address);
        Sounds.play("error");
        Toasts.show("Could not connect to “" + (d ? (d.name || d.deviceName || address) : address) + "”. Is it on and nearby?", { "icon": "bluetooth" });
    }
    function setPending(address, what) {
        const p = Object.assign({}, pending);
        if (what) p[address] = what; else delete p[address];
        pending = p;
    }
    // Connecting has no answer in BlueZ's API: watch the device until it
    // connects, falls back to disconnected, or 25 s pass.
    property var watches: []
    Timer {
        interval: 500; repeat: true; running: root.watches.length > 0
        onTriggered: {
            const keep = [];
            for (const w of root.watches) {
                const d = root.find(w.address);
                if (!d || d.connected) { root.setPending(w.address, ""); continue; }
                if (d.state === BluetoothDeviceState.Connecting) w.seen = true;
                const gaveUp = Date.now() - w.since > 25000;
                if (gaveUp || (d.state === BluetoothDeviceState.Disconnected && (w.seen || Date.now() - w.since > 4000))) {
                    root.setPending(w.address, "");
                    root.couldNot(w.address);
                    continue;
                }
                keep.push(w);
            }
            root.watches = keep;
        }
    }

    // Forgetting waits on an undo toast; BlueZ removes the device when it times out.
    function forget(item) {
        if (forgetting[item.address]) return;
        const address = item.address;
        mark(address, true);
        Toasts.undo("“" + item.name + "” forgotten", () => {
            root.mark(address, false);
            if (root.fake) { root.patch(f => f.devices = f.devices.filter(d => d.address !== address)); return; }
            const d = root.find(address);
            if (d) root.act(["bluetoothctl", "remove", address], () => d.forget());
        }, () => root.mark(address, false), "bluetooth");
    }
    function mark(address, on) {
        const f = Object.assign({}, forgetting);
        if (on) f[address] = true; else delete f[address];
        forgetting = f;
    }

    // -------------------------------------------------------------- pairing

    function pair(item) {
        if (pairing && pairing.step !== "failed") return;
        pairing = { "address": item.address, "name": item.name, "glyph": item.glyph, "step": "working", "passkey": "", "text": "" };
        if (fake) { simulatePair(item); return; }
        if (Sys.harness) { Sys.run(["bluetoothctl", "--agent", "KeyboardDisplay", "pair", item.address]); later(600, () => root.pairing = null); return; }
        pairer.address = item.address;
        pairer.buf = "";
        pairer.sent = false;
        pairer.done = false;
        pairer.running = true;
        pairClock.restart();
    }
    function step(s, extra) { if (pairing) pairing = Object.assign({}, pairing, { "step": s }, extra || {}); }
    function confirmPair(yes) {
        if (!pairing) return;
        if (fake) { simulateConfirm(yes); return; }
        send(yes ? "yes\n" : "no\n");
        step("working");
    }
    function enterPin(pin) {
        if (!pairing) return;
        if (fake) { step("working"); later(900, () => root.pairOk()); return; }
        send(pin + "\n");
        step("working");
    }
    function cancelPair() {
        if (!pairing) return;
        const p = pairing;
        pairing = null;
        if (fake) { queue = []; return; }
        if (pairer.running) {
            if (p.step === "confirm") send("no\n");
            else if (p.step === "pin") send("\n");
            send("cancel-pairing " + p.address + "\nquit\n");
            stopPairer.restart();
        }
    }
    function dismissPair() { pairing = null; }
    function send(text) { if (pairer.running) pairer.write(text); }

    function pairOk() {
        if (!pairing) return;
        const address = pairing.address;
        if (fake) patch(f => f.devices.forEach(d => { if (d.address === address) { d.paired = true; d.trusted = true; d.connected = true; d.state = BluetoothDeviceState.Connected; } }));
        pairing = null;
    }
    function pairFail(text) {
        step("failed", { "text": text });
        if (pairer.running) { send("quit\n"); stopPairer.restart(); }
    }
    function reason(code) {
        const c = (code || "").replace(/^org\.bluez\.Error\./, "");
        return {
            "AuthenticationFailed": "The codes did not match, or the device turned it down.",
            "AuthenticationCanceled": "Pairing was cancelled.",
            "AuthenticationRejected": "The device turned the pairing down.",
            "AuthenticationTimeout": "The device took too long to answer.",
            "ConnectionAttemptFailed": "The device did not answer. Make sure it is in pairing mode and close by.",
            "InProgress": "Already pairing with this device."
        }[c] || "Pairing failed (" + (c || "unknown error") + ").";
    }

    // bluetoothctl with a KeyboardDisplay agent, driven line by line. Its
    // prompts end without a newline, so read whatever arrives.
    Process {
        id: pairer
        property string address: ""
        property string buf: ""
        property bool sent: false
        property bool done: false
        command: ["bluetoothctl", "--agent", "KeyboardDisplay"]
        stdinEnabled: true
        stdout: SplitParser { splitMarker: ""; onRead: chunk => root.heard(chunk) }
        onStarted: startPair.restart()
        onExited: {
            pairClock.stop();
            if (root.pairing && root.pairing.address === address && !done && root.pairing.step !== "failed") root.pairFail("Pairing stopped before it finished.");
        }
    }
    // Pair once the agent is up (or after a moment if it never says so).
    Timer { id: startPair; interval: 3000; onTriggered: root.beginPair() }
    function beginPair() {
        if (pairer.sent || !pairer.running) return;
        pairer.sent = true;
        startPair.stop();
        send("default-agent\npair " + pairer.address + "\n");
    }
    Timer { id: pairClock; interval: 90000; onTriggered: { root.send("cancel-pairing " + pairer.address + "\n"); root.pairFail("The device took too long to answer."); } }
    Timer { id: stopPairer; interval: 1500; onTriggered: pairer.running = false }
    function heard(chunk) {
        pairer.buf += chunk.replace(/\x1b\[[0-9;?]*[A-Za-z]/g, "").replace(/\r/g, "\n");
        const a = pairer.address;
        const rules = [
            [/Agent registered|Agent is already registered|Failed to register agent/, () => Qt.callLater(root.beginPair)],
            [/Confirm passkey (\d+)/, m => root.step("confirm", { "passkey": m[1] })],
            [/Passkey: (\d+)/, m => root.step("display", { "passkey": m[1] })],
            [/Enter PIN code:|Enter passkey \(number in 0-999999\):/, () => root.step("pin", { "passkey": "" })],
            [/Accept pairing \(yes\/no\):|Authorize service \S+ \(yes\/no\):/, () => root.send("yes\n")],
            [/Pairing successful|org\.bluez\.Error\.AlreadyExists/, () => { root.step("connecting"); root.send("trust " + a + "\nconnect " + a + "\n"); }],
            [/Failed to pair: (\S+)/, m => root.pairFail(root.reason(m[1]))],
            [/Device \S+ not available/, () => root.pairFail("The device is no longer in range.")],
            [/Connection successful/, () => root.pairEnd(true)],
            [/Failed to connect: \S+/, () => root.pairEnd(false)]
        ];
        for (;;) {
            let best = null;
            for (const r of rules) {
                const m = r[0].exec(pairer.buf);
                if (m && (!best || m.index < best.m.index)) best = { "m": m, "fn": r[1] };
            }
            if (!best) break;
            pairer.buf = pairer.buf.slice(best.m.index + best.m[0].length);
            best.fn(best.m);
        }
        if (pairer.buf.length > 4000) pairer.buf = pairer.buf.slice(-1000);
    }
    function pairEnd(connected) {
        pairer.done = true;
        const name = pairing ? pairing.name : "";
        pairing = null;
        if (!connected) Toasts.show("Paired with “" + name + "”, but it did not connect yet.", { "icon": "bluetooth" });
        send("quit\n");
        stopPairer.restart();
    }

    // ------------------------------------------------------------ fixtures

    function patch(fn) { const f = JSON.parse(JSON.stringify(fx)); fn(f); fx = f; }
    property var queue: []
    function later(ms, fn) { queue = queue.concat([{ "at": Date.now() + ms, "fn": fn }]); }
    Timer {
        interval: 100; repeat: true; running: root.queue.length > 0
        onTriggered: {
            const now = Date.now(), due = root.queue.filter(q => q.at <= now);
            root.queue = root.queue.filter(q => q.at > now);
            for (const q of due) q.fn();
        }
    }
    function simulatePair(item) {
        if ((fx.failing || {})[item.address]) { later(1500, () => root.pairFail(root.reason("org.bluez.Error.ConnectionAttemptFailed"))); return; }
        if (item.glyph === "phone") { later(900, () => root.step("confirm", { "passkey": "482913" })); return; }
        if (item.glyph === "keyboard") { later(900, () => root.step("display", { "passkey": "730264" })); later(6000, () => { if (root.pairing && root.pairing.step === "display") root.pairOk(); }); return; }
        if (item.glyph === "gamepad") { later(900, () => root.step("pin")); return; }
        later(1500, () => root.pairOk());
    }
    function simulateConfirm(yes) {
        if (!yes) { pairFail(reason("AuthenticationCanceled")); return; }
        step("connecting");
        later(1100, () => root.pairOk());
    }

    function setFixture(name) {
        fixture = name || "";
        fx = fixture ? fixtures(fixture) : ({});
        pairing = null; forgetting = ({}); pending = ({}); queue = [];
    }
    function fixtures(name) {
        const S = BluetoothDeviceState;
        let n = 0;
        const dev = (name, icon, paired, connected, battery) => ({
            "address": "F4:33:B7:0B:" + (16 + n).toString(16).toUpperCase() + ":" + (16 + (n++ * 7) % 200).toString(16).toUpperCase(),
            "name": name, "deviceName": name, "icon": icon, "paired": paired, "bonded": paired, "trusted": paired, "connected": connected, "pairing": false,
            "state": connected ? S.Connected : S.Disconnected, "batteryAvailable": battery >= 0, "battery": Math.max(0, battery)
        });
        if (name === "unavailable") return { "available": false, "on": false, "name": "", "devices": [] };
        if (name === "empty") return { "available": true, "on": true, "name": "bonhart", "discovering": false, "devices": [] };
        const normal = [
            dev("Mariano’s AirPods Pro", "audio-headset", true, true, 0.8), dev("MX Master 4", "input-mouse", true, true, 0.55),
            dev("MX Keys Mini", "input-keyboard", true, false, -1), dev("Pixel 8", "phone", true, false, -1),
            dev("JBL Flip 6", "audio-card", false, false, -1), dev("Galaxy Buds2 Pro", "audio-headset", false, false, -1),
            dev("Xbox Wireless Controller", "input-gaming", false, false, -1), dev("Galaxy S24 de Lucía", "phone", false, false, -1),
            dev("Old Sony speaker", "audio-card", false, false, -1), dev("F8-DE-E8-83-CF-ED", "", false, false, -1)
        ];
        const failing = {};
        failing[normal[8].address] = true;
        failing[normal[2].address] = true;
        if (name === "off") return { "available": true, "on": false, "name": "bonhart", "discovering": false, "devices": normal.slice(0, 4), "failing": failing };
        if (name === "stress") {
            const long = " — the one with the cracked case that lives in the drawer of the desk by the window";
            const icons = ["audio-headset", "input-mouse", "input-keyboard", "phone", "audio-card", "input-gaming", "computer", "", "printer", "camera-video"];
            const list = [];
            for (let i = 0; i < 16; i++)
                list.push(dev(["Sony WH-1000XM5", "MX Master 3S", "Keychron K3 Pro", "iPhone 15 Pro", "Bose SoundLink", "DualSense", "MacBook Air", "Fitbit Charge 6 watch", "HP OfficeJet", "Logitech Brio"][i % 10]
                              + (i < 10 ? long : " " + (i + 1)), icons[i % 10], true, i < 7, i % 3 === 0 ? (i * 0.07) % 1 : -1));
            for (let i = 0; i < 22; i++)
                list.push(dev("Nearby device " + (i + 1) + (i % 3 === 0 ? long : ""), icons[(i + 3) % 10], false, false, -1));
            list[0].battery = 0.05;
            list[1].battery = 1;
            return { "available": true, "on": true, "name": "bonhart-3 the laptop on the desk by the window, third floor, Monarch MD office", "discovering": true, "devices": list, "failing": {} };
        }
        return { "available": true, "on": true, "name": "bonhart", "discovering": false, "devices": normal, "failing": failing };
    }

    IpcHandler {
        target: "bluetooth"
        // normal | stress | empty | off | unavailable, or "" for live.
        function fixture(name: string): void { root.setFixture(name === "live" ? "" : name); }
        function power(on: bool): void { root.setOn(on); }
        function scan(on: bool): void { root.setDiscovering(on); }
        // By name or address: what clicking a device on the page does.
        function pair(name: string): void { const it = root.items.find(i => i.name === name || i.address === name); if (it) root.pair(it); }
        function connect(name: string): void { const it = root.items.find(i => i.name === name || i.address === name); if (it) root.toggle(it); }
        function forget(name: string): void { const it = root.items.find(i => i.name === name || i.address === name); if (it) root.forget(it); }
        function confirm(yes: bool): void { root.confirmPair(yes); }
        function pin(code: string): void { root.enterPin(code); }
        function cancel(): void { root.cancelPair(); }
        function state(): string {
            return JSON.stringify({ "fixture": root.fixture, "on": root.on, "discovering": root.discovering, "pairing": root.pairing,
                                    "items": root.items.map(i => i.name + (i.connected ? " [on]" : "") + (i.paired ? " [paired]" : "")) });
        }
    }
}
