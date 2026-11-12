import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth as QB
import qs.Common
import qs.Services
import "Fixtures.js" as Fixtures

// What the sidebar shows: the live services, or a fixture (normal, stress,
// empty) for tests. In a fixture every action stays local, so a test can
// press anything without touching the real system.
Item {
    id: feed

    property string fixture: ""
    readonly property bool fake: fixture !== ""
    property var fx: ({})
    property real now: Date.now()
    property bool ticking: false
    signal closeRequested()

    // Read `fixture` itself here: `fake` may not have caught up yet.
    onFixtureChanged: { fx = fixture !== "" ? Fixtures.make(fixture, Date.now(), Settings.get("weather.place")) : ({}); hidden = ({}); }
    function patch(key, values) {
        const f = Object.assign({}, fx);
        f[key] = Object.assign({}, fx[key], values);
        fx = f;
    }
    function list(x) { const out = []; for (let i = 0; i < (x ? x.length : 0); i++) out.push(x[i]); return out; }

    Timer {
        interval: 1000; repeat: true; running: feed.ticking; triggeredOnStart: true
        onTriggered: {
            feed.now = Date.now();
            // A playing fixture keeps moving.
            if (feed.fake && feed.fx.media && feed.fx.media.playing && feed.fx.media.length > 0)
                feed.patch("media", { "position": (feed.fx.media.position + 1) % feed.fx.media.length });
        }
    }

    // Hero
    readonly property string weather: fake ? fx.weather : Weather.summary

    // Wi-Fi
    readonly property var wifi: fake ? fx.wifi : { "on": Network.wifiOn, "ssid": Network.ssid, "signal": Network.signal, "wired": Network.wired, "networks": Network.networks }
    function setWifi(v) { if (fake) patch("wifi", { "on": v }); else Network.setWifi(v); }
    function scan() { if (!fake) Network.scan(); }
    function join(ssid) {
        if (fake) patch("wifi", { "ssid": ssid, "networks": fx.wifi.networks.map(n => Object.assign({}, n, { "active": n.ssid === ssid })) });
        // A secured network not yet saved needs a password: Settings › Network asks for it.
        else if (!Network.join(ssid, "")) Network.ask(ssid);
    }

    // Bluetooth: paired and connected devices.
    readonly property var bt: fake ? fx.bt : {
        "available": Bluetooth.available, "on": Bluetooth.on, "summary": Bluetooth.summary,
        "devices": Bluetooth.devices.filter(d => d.paired || d.connected).map(d => ({
            "name": d.name || d.deviceName || "Device", "connected": d.connected, "battery": d.batteryAvailable ? d.battery : -1,
            "busy": d.state === QB.BluetoothDeviceState.Connecting || d.state === QB.BluetoothDeviceState.Disconnecting, "ref": d
        })).sort((a, b) => b.connected - a.connected)
    }
    function setBt(v) { if (fake) patch("bt", { "on": v }); else Bluetooth.setOn(v); }
    function toggleDevice(d) {
        if (fake) { patch("bt", { "devices": fx.bt.devices.map(x => x.name === d.name ? Object.assign({}, x, { "connected": !x.connected }) : x) }); return; }
        if (!d.ref) return;
        Bluetooth.toggle(Bluetooth.describe(d.ref));
    }

    // Focus
    readonly property bool focusActive: fake ? fx.focus.ends > now : Focus.active
    readonly property real focusEnds: fake ? fx.focus.ends : Focus.endsAt
    readonly property int focusDuration: fake ? fx.focus.duration : Focus.duration
    readonly property int focusLeft: fake ? Math.max(0, Math.round((fx.focus.ends - now) / 1000)) : Focus.remaining
    readonly property real focusProgress: focusActive ? 1 - focusLeft / Math.max(1, focusDuration) : 0
    readonly property string focusClock: {
        const s = focusActive ? focusLeft : focusDuration;
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
    function toggleFocus() {
        if (fake) patch("focus", { "ends": focusActive ? 0 : Date.now() + fx.focus.duration * 1000 });
        else Focus.toggle();
    }

    // VPN. Turning it off waits for an undo toast: on a machine reached over
    // Tailscale, a stray tap should not cut the line.
    property bool vpnLeaving: false
    readonly property var vpn: fake ? fx.vpn : { "available": Tailscale.available, "on": Tailscale.on && !vpnLeaving, "summary": vpnLeaving ? "Turning off" : Tailscale.summary, "canToggle": Tailscale.canToggle, "busy": Tailscale.busy }
    function setVpn(v) {
        if (fake) { patch("vpn", { "on": v, "summary": v ? "214 peers" : "Off" }); return; }
        if (v) { Tailscale.setOn(true); return; }
        vpnLeaving = true;
        Toasts.undo("Tailscale turns off", () => { feed.vpnLeaving = false; Tailscale.setOn(false); }, () => feed.vpnLeaving = false, "shield");
    }

    // Keep awake
    readonly property bool awake: fake ? fx.awake : Awake.on
    function toggleAwake() { if (fake) { const f = Object.assign({}, fx); f.awake = !fx.awake; fx = f; } else Awake.toggle(); }

    // Night light: only with wlsunset or gammastep installed.
    property string nightTool: ""
    property bool nightOn: false
    readonly property var night: fake ? fx.night : { "available": nightTool !== "", "on": nightOn }
    function toggleNight() { if (fake) patch("night", { "on": !fx.night.on }); else nightOn = !nightOn; }
    Process {
        running: true
        command: ["sh", "-c", "command -v wlsunset >/dev/null && echo wlsunset || { command -v gammastep >/dev/null && echo gammastep; } || true"]
        stdout: StdioCollector { onStreamFinished: feed.nightTool = text.trim() }
    }
    Process {
        running: feed.nightOn && feed.nightTool !== "" && !feed.fake
        command: feed.nightTool === "wlsunset" ? ["wlsunset", "-T", "4001", "-t", "4000", "-S", "00:00", "-s", "23:59"] : ["gammastep", "-P", "-O", "4000"]
    }

    // Audio
    readonly property real volume: fake ? fx.volume : Audio.volume
    readonly property bool muted: fake ? fx.muted : Audio.muted
    readonly property var outputs: fake ? fx.outputs : Audio.outputs.map(n => ({ "name": n.description || n.nickname || n.name, "current": n === Audio.sink, "ref": n }))
    readonly property string device: fake ? fx.device : Audio.device
    readonly property bool deviceBt: fake ? fx.deviceBt : (Audio.sink !== null && /bluez/i.test(Audio.sink.name || ""))
    function setVolume(v) { if (fake) { const f = Object.assign({}, fx); f.volume = v; f.muted = false; fx = f; } else Audio.setVolume(v); }
    function useOutput(o) {
        if (fake) { const f = Object.assign({}, fx); f.outputs = fx.outputs.map(x => Object.assign({}, x, { "current": x.name === o.name })); f.device = o.name; fx = f; }
        else Audio.useOutput(o.ref);
    }

    // Brightness
    readonly property bool hasBrightness: fake || Brightness.available
    readonly property real brightness: fake ? fx.brightness : Brightness.level
    function setBrightness(v) { if (fake) { const f = Object.assign({}, fx); f.brightness = v; fx = f; } else Brightness.set(v); }

    // Media
    readonly property var media: fake ? fx.media : {
        "active": Media.active, "playing": Media.playing, "title": Media.title, "artist": Media.artist, "art": Media.art,
        "length": Media.length, "position": Media.position, "canSeek": Media.player !== null && Media.player.canSeek,
        "resume": Media.player !== null && !Media.active && Media.title ? { "title": Media.title, "artist": Media.artist } : null,
        "canPlay": Media.player !== null
    }
    function playPause() { if (fake) patch("media", { "playing": !fx.media.playing, "active": true }); else if (Media.player && !Media.active) Media.player.play(); else Media.toggle(); }
    function next() { if (!fake) Media.next(); }
    function previous() { if (!fake) Media.previous(); }
    function seek(s) { if (fake) patch("media", { "position": s }); else Media.seek(s); }

    // World clock, calendar, quota
    readonly property var cities: fake ? fx.cities : (Settings.get("world.cities") || [])
    readonly property bool calConnected: fake ? fx.calendar.connected : Calendar.connected
    readonly property var events: fake ? fx.calendar.events : Calendar.events
    readonly property var quota: fake ? fx.quota : Quota.rows

    // Notifications: groups of plain notes; `ref` is the live Notification.
    property var hidden: ({})
    readonly property bool quiet: fake ? focusActive : Notifs.quiet
    readonly property string quietReason: fake ? (focusActive ? "focus" : "") : Notifs.quietReason
    readonly property var groups: fake
        ? fx.groups.map(g => Object.assign({}, g, { "items": g.items.filter(n => !hidden[n.id]) })).filter(g => g.items.length > 0)
        : Notifs.groups.map(g => ({ "app": g.app, "icon": g.icon, "count": g.items.length, "items": g.items.map(n => feed.toNote(n)) }))
    readonly property string since: {
        if (fake) return fx.since;
        const h = Notifs.history[0];
        return h ? Qt.formatTime(new Date(h.time), "HH:mm") : "";
    }
    function toNote(n) {
        const acts = list(n.actions);
        return {
            "id": n.id, "summary": n.summary || "", "body": n.body || "", "image": n.image || "", "icon": n.appIcon || "",
            "actions": acts.filter(a => a.identifier !== "default" && a.text).map(a => ({ "text": a.text, "ref": a })),
            "hasDefault": acts.some(a => a.identifier === "default"), "ref": n
        };
    }
    function ago(n) { return fake ? n.ago : (n.ref ? Notifs.ago(n.ref) : ""); }
    function dismiss(notes) {
        if (!fake) { Notifs.dismiss(notes.map(n => n.ref)); return; }
        const ids = notes.map(n => n.id);
        const h = Object.assign({}, hidden);
        for (const id of ids) h[id] = true;
        hidden = h;
        Toasts.undo(ids.length === 1 ? "Notification dismissed" : ids.length + " notifications cleared", () => {}, () => {
            const r = Object.assign({}, feed.hidden);
            for (const id of ids) delete r[id];
            feed.hidden = r;
        }, "bell");
    }
    function clearAll() {
        if (!fake) { Notifs.clearAll(); return; }
        dismiss([].concat.apply([], groups.map(g => g.items)));
    }
    function activate(n, action) {
        if (fake) return;
        if (action) Notifs.invoke(n.ref, action.ref);
        else { const d = list(n.ref.actions).find(a => a.identifier === "default"); if (d) Notifs.invoke(n.ref, d); }
        closeRequested();
    }

    // Footer
    readonly property var battery: fake ? fx.battery : { "present": Battery.present, "percent": Battery.percent, "label": Battery.timeLabel, "low": Battery.low, "charging": Battery.charging }
    function lock() { if (!fake) { closeRequested(); Power.lock(); } }
    function power(what) {
        closeRequested();
        if (fake) return;
        if (what === "hibernate") Power.hibernate();
        else if (what === "reboot") Power.reboot();
        else if (what === "poweroff") Power.poweroff();
        else if (what === "logout") Power.logout();
    }
}
