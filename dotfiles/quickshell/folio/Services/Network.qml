pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// NetworkManager through nmcli: Wi-Fi (the network in use with its details,
// the networks in range, the saved ones), Ethernet and NetworkManager VPNs.
// Reads refresh when `nmcli monitor` reports, and every few seconds while a
// page watches (watch/unwatch).
//
// Writes go through Sys.run, so the harness only records them. Joining runs
// nmcli itself to hear how it went: a password travels on the process's
// stdin into a 600 file under $XDG_RUNTIME_DIR that nmcli reads
// (passwd-file) and that is removed after; it never appears on a command line.
//
// Fixtures (IPC `network fixture normal|stress|empty|off|unavailable`, "" for
// live) replace nmcli's raw output with a made-up machine; every action then
// changes the fixture, never the system.
Singleton {
    id: root

    // ------------------------------------------------------------ the model
    readonly property var model: shape(fake ? fxRaw : liveRaw)
    readonly property bool wifiAvailable: model.wifiAvailable
    readonly property bool wifiHardware: model.wifiHardware      // false: a hardware switch or rfkill
    readonly property bool wifiOn: model.wifiOn
    readonly property string wifiDevice: model.wifiDevice
    readonly property var current: model.current                 // the Wi-Fi network in use, with details, or null
    readonly property string ssid: current ? current.ssid : ""
    readonly property int signal: current ? current.signal : 0
    readonly property string connecting: model.connecting        // a network NetworkManager is bringing up
    readonly property var networks: model.networks               // in range, one per name: in use, saved, then by signal
    readonly property var known: model.known                     // saved Wi-Fi networks
    readonly property var ethernet: model.ethernet               // [{device, connected, carrier, speed, ip4…}]
    readonly property bool wired: ethernet.some(e => e.connected)
    readonly property bool online: !!current || wired
    readonly property var vpns: model.vpns                       // NetworkManager VPN and WireGuard profiles

    // What this shell is doing.
    property string joining: ""          // the network being joined
    property var joinError: ({})         // {ssid, kind: "password" | "failed" | "unsupported", text}
    property bool scanning: false
    property string prompt: ""           // a network to ask a password for (Settings › Network opens at it)
    property bool promptHidden: false    // open the hidden-network form
    property var forgetting: ({})        // uuid → true while its undo toast is up
    property bool wifiLeaving: false     // Wi-Fi off, waiting on its undo toast
    property int wifiToast: 0
    property string leaving: ""          // uuid of a disconnect waiting on its undo toast

    property string fixture: ""
    readonly property bool fake: fixture !== ""
    property var fxRaw: ({})
    property var liveRaw: ({})
    property var ssidOf: ({})            // saved profile uuid → {ssid, hidden}
    property int watchers: 0

    // A page that shows networks: refresh often, and look for networks now.
    function watch() { watchers++; wantScan = !fake; refresh(); }
    property bool wantScan: false
    function unwatch() { watchers = Math.max(0, watchers - 1); }

    // ------------------------------------------------------------- actions

    function refresh() { if (fake) return; if (status.running) again = true; else status.running = true; }
    property bool again: false
    function scan() {
        if (scanning) return;
        scanning = true;
        if (fake) { later(1600, () => root.scanning = false); return; }
        scanner.running = true;
    }

    function setWifi(on) {
        wifiLeaving = false;
        if (wifiToast) { Toasts.take(wifiToast); wifiToast = 0; }
        if (fake) {
            patch(r => {
                r.wifiOn = on;
                const dev = r.devices.find(d => d.type === "wifi");
                if (on) { r.aps = r.apsOff || r.aps; if (dev) dev.state = "disconnected"; }
                else { r.apsOff = r.aps; r.aps = []; if (dev) { dev.state = "unavailable"; dev.uuid = ""; } r.cons.forEach(c => { if (c.type === "802-11-wireless") c.active = false; }); }
            });
            return;
        }
        if (Sys.run(["nmcli", "radio", "wifi", on ? "on" : "off"])) liveRaw = Object.assign({}, liveRaw, { "wifiOn": on });
    }
    // Turning Wi-Fi off while it carries the connection waits on an undo
    // toast: on a laptop reached over the network, a stray tap should not cut the line.
    function turnWifiOff() {
        if (!current) { setWifi(false); return; }
        wifiLeaving = true;
        wifiToast = Toasts.undo("Wi-Fi turns off", () => { root.wifiToast = 0; if (root.wifiLeaving) root.setWifi(false); },
                                () => { root.wifiToast = 0; root.wifiLeaving = false; }, "wifi");
    }

    // Joins a network by name. Returns false when it needs a password first
    // (secured, not saved, none given): the caller asks for one, inline on the
    // page, or ask(ssid) to open Settings › Network at it. opts: {hidden, kind}.
    function join(name, password, opts) {
        opts = opts || {};
        if (joining !== "") return true;
        const n = networks.find(x => x.ssid === name) || null;
        const saved = known.find(k => k.ssid === name && !forgetting[k.uuid]) || null;
        const kind = opts.hidden ? (opts.kind || "psk") : (n ? n.kind : saved ? saved.kind : "psk");
        if (!saved && (kind === "enterprise" || kind === "wep")) {
            joinError = { "ssid": name, "kind": "unsupported", "text": kind === "wep" ? "WEP is too old to trust; join it with nmcli if you must." : "Enterprise networks need a certificate or a login; set them up with nmcli or nm-connection-editor." };
            return true;
        }
        let mode;
        if (saved && !password) mode = "up";
        else if (kind === "open") mode = "open";
        else if (!password) return false;
        else mode = saved ? "uppw" : "new";
        joinError = {};
        joining = name;
        prompt = "";
        if (fake) { simulateJoin(name, password, mode, opts); return true; }
        const km = kind === "sae" ? "sae" : "wpa-psk";
        const hidden = opts.hidden ? "yes" : "no";
        const shown = {
            "up": ["nmcli", "-w", "45", "connection", "up", "uuid", saved ? saved.uuid : ""],
            "open": ["nmcli", "-w", "45", "device", "wifi", "connect", name, "hidden", hidden],
            "uppw": ["nmcli", "-w", "45", "connection", "up", "uuid", saved ? saved.uuid : "", "passwd-file", "$XDG_RUNTIME_DIR/folio-wifi.XXXXXX"],
            "new": ["nmcli", "connection", "add", "type", "wifi", "con-name", name, "ssid", name, "802-11-wireless.hidden", hidden, "wifi-sec.key-mgmt", km,
                    "&&", "nmcli", "-w", "45", "connection", "up", "uuid", "<new>", "passwd-file", "$XDG_RUNTIME_DIR/folio-wifi.XXXXXX"]
        }[mode];
        if (Sys.harness) { Sys.run(shown); joining = ""; return true; }
        joiner.secret = password || "";
        joiner.mode = mode;
        joiner.command = ["sh", "-c", joinScript, "folio-join", mode, name, saved ? saved.uuid : "", hidden, km];
        joiner.running = true;
        return true;
    }
    function connect(name) { join(name, ""); }   // older callers
    function ask(name) { prompt = name; Shell.openSettings("network"); }
    function askHidden() { promptHidden = true; Shell.openSettings("network"); }
    function clearError() { joinError = {}; }

    function disconnect(uuid) {
        leaving = "";
        if (fake) {
            patch(r => {
                r.cons.forEach(c => { if (c.uuid === uuid) c.active = false; });
                r.devices.forEach(d => { if (d.uuid === uuid) { d.uuid = ""; d.state = "disconnected"; } });
                r.aps.forEach(a => a.inUse = false);
            });
            return;
        }
        if (Sys.run(["nmcli", "connection", "down", "uuid", uuid])) refreshSoon();
    }
    function disconnectSoon() {
        if (!current) return;
        const c = current;
        leaving = c.uuid;
        Toasts.undo("Disconnecting from “" + c.ssid + "”", () => { if (root.leaving === c.uuid) root.disconnect(c.uuid); }, () => root.leaving = "", "wifi");
    }

    // Forgetting waits on an undo toast; the profile is deleted when it times out.
    function forget(uuid, name) {
        if (!uuid || forgetting[uuid]) return;
        mark(uuid, true);
        Toasts.undo("“" + name + "” forgotten", () => {
            root.mark(uuid, false);
            if (root.fake) root.patch(r => {
                r.cons = r.cons.filter(c => c.uuid !== uuid);
                r.devices.forEach(d => { if (d.uuid === uuid) { d.uuid = ""; d.state = "disconnected"; r.aps.forEach(a => a.inUse = false); } });
            });
            else if (Sys.run(["nmcli", "connection", "delete", "uuid", uuid])) root.refreshSoon();
        }, () => root.mark(uuid, false), "wifi");
    }
    function mark(uuid, on) {
        const f = Object.assign({}, forgetting);
        if (on) f[uuid] = true; else delete f[uuid];
        forgetting = f;
    }

    function setAutoconnect(uuid, on) {
        if (fake) { patch(r => r.cons.forEach(c => { if (c.uuid === uuid) c.autoconnect = on; })); return; }
        if (Sys.run(["nmcli", "connection", "modify", "uuid", uuid, "connection.autoconnect", on ? "yes" : "no"])) refreshSoon();
    }
    function setVpn(uuid, up) {
        if (fake) {
            patch(r => r.cons.forEach(c => { if (c.uuid === uuid) { c.active = up; c.state = up ? "activating" : ""; } }));
            if (up) later(1200, () => root.patch(r => r.cons.forEach(c => { if (c.uuid === uuid && c.active) c.state = "activated"; })));
            return;
        }
        if (Sys.run(["nmcli", "connection", up ? "up" : "down", "uuid", uuid])) refreshSoon();
    }

    // -------------------------------------------------------------- joining

    // $1 mode (up, uppw, open, new), $2 name, $3 saved uuid, $4 hidden, $5 key-mgmt.
    // The password arrives on stdin and goes only to a 600 file nmcli reads.
    readonly property string joinScript: "
set -u
mode=$1 name=$2 uuid=$3 hidden=$4 km=$5 f=
trap '[ -n \"$f\" ] && rm -f \"$f\"' EXIT
trap 'exit 130' HUP INT TERM
secret() {
  umask 077
  f=$(mktemp \"${XDG_RUNTIME_DIR:?}/folio-wifi.XXXXXX\") || exit 90
  IFS= read -r pw || exit 91
  printf '802-11-wireless-security.psk:%s\\n' \"$pw\" > \"$f\"
  pw=
}
case $mode in
  up) nmcli -w 45 connection up uuid \"$uuid\"; exit $? ;;
  open) nmcli -w 45 device wifi connect \"$name\" hidden \"$hidden\"; exit $? ;;
  uppw) secret; nmcli -w 45 connection up uuid \"$uuid\" passwd-file \"$f\"; exit $? ;;
  new)
    secret
    uuid=$(cat /proc/sys/kernel/random/uuid)
    nmcli connection add type wifi con-name \"$name\" ssid \"$name\" connection.uuid \"$uuid\" \\
      802-11-wireless.hidden \"$hidden\" wifi-sec.key-mgmt \"$km\" >/dev/null || exit 92
    nmcli -w 45 connection up uuid \"$uuid\" passwd-file \"$f\"
    rc=$?
    [ \"$rc\" -eq 0 ] || nmcli connection delete uuid \"$uuid\" >/dev/null 2>&1
    exit $rc ;;
esac
"
    Process {
        id: joiner
        property string secret: ""
        property string mode: ""
        stdinEnabled: true
        onStarted: { if (mode === "uppw" || mode === "new") write(secret + "\n"); secret = ""; }
        stderr: StdioCollector { id: joinErr }
        stdout: StdioCollector {}
        // Let stderr finish arriving before reading it.
        onExited: code => Qt.callLater(() => {
            const name = root.joining;
            root.joining = "";
            secret = "";
            root.joinError = code === 0 ? {} : root.failure(name, code, joinErr.text);
            root.refresh();
        })
    }
    // nmcli's complaint, in words: a wrong password, or something else.
    function failure(name, code, text) {
        const t = (text || "").replace(/^Error:\s*/m, "").trim();
        if (/secrets were required|no-secrets|psk|authenticat|802-1x supplicant/i.test(t))
            return { "ssid": name, "kind": "password", "text": "Wrong password. Check it and try again." };
        if (code === 3 || /timeout|timed out/i.test(t))
            return { "ssid": name, "kind": "failed", "text": "“" + name + "” did not answer in time." };
        if (/no network with ssid/i.test(t))
            return { "ssid": name, "kind": "failed", "text": "“" + name + "” is not in range." };
        const line = t.split("\n").filter(l => l).pop() || "";
        return { "ssid": name, "kind": "failed", "text": line ? line.replace(/^Connection activation failed:\s*/i, "Could not join: ") : "Could not join “" + name + "”." };
    }

    // ------------------------------------------------------------- reading

    // One pass over everything NetworkManager knows; sections split by "#name".
    Process {
        id: status
        command: ["sh", "-c", "nmcli -t -f WIFI,WIFI-HW radio; echo '#dev'; nmcli -t -f DEVICE,TYPE,STATE,CON-UUID device; "
            + "echo '#show'; nmcli -t -f GENERAL.DEVICE,GENERAL.HWADDR,CAPABILITIES.SPEED,WIRED-PROPERTIES.CARRIER,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS,IP6.GATEWAY,IP6.DNS device show; "
            + "echo '#con'; nmcli -t -f NAME,UUID,TYPE,AUTOCONNECT,ACTIVE,STATE,TIMESTAMP connection show; "
            + "echo '#ap'; nmcli -t -f IN-USE,SIGNAL,SECURITY,FREQ,CHAN,RATE,BSSID,SSID device wifi list --rescan no"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = root.parse(text);
                if (JSON.stringify(raw) !== JSON.stringify(root.liveRaw)) root.liveRaw = raw;
                if (root.wantScan && raw.wifiOn) { root.wantScan = false; root.scan(); }
                // Saved Wi-Fi profiles' network names, read again when the set changes.
                const ids = raw.cons.filter(c => c.type === "802-11-wireless").map(c => c.uuid);
                if (ids.join(",") !== root.knownKey && !names.running) {
                    root.knownKey = ids.join(",");
                    names.command = ["sh", "-c", "for u in \"$@\"; do echo \"#$u\"; nmcli -t -f 802-11-wireless.ssid,802-11-wireless.hidden,802-11-wireless-security.key-mgmt connection show uuid \"$u\"; done", "folio-ssids"].concat(ids);
                    names.running = true;
                }
            }
        }
        onExited: if (root.again) { root.again = false; running = true; }
    }
    property string knownKey: "-"
    Process {
        id: names
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                let cur = null;
                for (const l of text.split("\n")) {
                    if (l.startsWith("#")) { cur = { "ssid": "", "hidden": false, "keyMgmt": "" }; map[l.slice(1)] = cur; continue; }
                    if (!cur || !l) continue;
                    const f = root.fields(l), v = f.slice(1).join(":");
                    if (f[0] === "802-11-wireless.ssid") cur.ssid = v;
                    else if (f[0] === "802-11-wireless.hidden") cur.hidden = v === "yes";
                    else if (f[0] === "802-11-wireless-security.key-mgmt") cur.keyMgmt = v;
                }
                root.ssidOf = map;
                root.liveRaw = Object.assign({}, root.liveRaw, { "ssids": map });
            }
        }
    }
    Process {
        id: scanner
        command: ["nmcli", "-t", "-f", "SSID", "device", "wifi", "list", "--rescan", "yes"]
        stdout: StdioCollector {}
        onExited: { root.scanning = false; root.refresh(); }
    }
    // The monitor dies with the shell (a killed shell would leave it running).
    Process {
        running: true
        command: ["sh", "-c", "command -v setpriv >/dev/null && exec setpriv --pdeathsig TERM nmcli monitor; exec nmcli monitor"]
        stdout: SplitParser { onRead: _ => debounce.restart() }
    }
    Timer { id: debounce; interval: 400; onTriggered: root.refresh() }
    Timer { interval: 8000; repeat: true; running: root.watchers > 0 && !root.fake; onTriggered: root.refresh() }
    function refreshSoon() { debounce.restart(); }
    Component.onCompleted: refresh()

    // nmcli -t: fields split on ':'; '\:' and '\\' are escapes.
    function fields(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) { cur += line[++i]; continue; }
            if (c === ":") { out.push(cur); cur = ""; continue; }
            cur += c;
        }
        out.push(cur);
        return out;
    }
    // nmcli's text → the raw form fixtures also use.
    function parse(text) {
        const sec = { "radio": [] };
        let cur = "radio";
        for (const l of text.split("\n")) {
            if (/^#[a-z]+$/.test(l)) { cur = l.slice(1); sec[cur] = []; continue; }
            sec[cur].push(l);
        }
        const radio = fields(sec.radio[0] || "");
        const raw = { "wifiOn": radio[0] === "enabled", "wifiHw": radio[1] !== "disabled", "devices": [], "show": {}, "cons": [], "aps": [], "ssids": ssidOf };
        for (const l of sec.dev || []) {
            if (!l) continue;
            const f = fields(l);
            raw.devices.push({ "device": f[0], "type": f[1], "state": f[2], "uuid": f[3] || "" });
        }
        let blk = null;
        for (const l of sec.show || []) {
            if (!l) { blk = null; continue; }
            const f = fields(l), key = f[0], v = f.slice(1).join(":");
            if (key === "GENERAL.DEVICE") { blk = { "mac": "", "speed": "", "carrier": false, "ip4": [], "ip6": [], "gateway": "", "gateway6": "", "dns": [] }; raw.show[v] = blk; continue; }
            if (!blk) continue;
            if (key === "GENERAL.HWADDR") blk.mac = v;
            else if (key === "CAPABILITIES.SPEED") blk.speed = /^\d/.test(v) ? v : "";
            else if (key === "WIRED-PROPERTIES.CARRIER") blk.carrier = v === "on";
            else if (key.startsWith("IP4.ADDRESS")) blk.ip4.push(v);
            else if (key === "IP4.GATEWAY") blk.gateway = v;
            else if (key.startsWith("IP6.ADDRESS")) blk.ip6.push(v);
            else if (key === "IP6.GATEWAY") blk.gateway6 = v;
            else if (key.startsWith("IP4.DNS") || key.startsWith("IP6.DNS")) blk.dns.push(v);
        }
        for (const l of sec.con || []) {
            if (!l) continue;
            const f = fields(l);
            raw.cons.push({ "name": f[0], "uuid": f[1], "type": f[2], "autoconnect": f[3] === "yes", "active": f[4] === "yes", "state": f[5] || "", "timestamp": Number(f[6]) || 0 });
        }
        for (const l of sec.ap || []) {
            if (!l) continue;
            const f = fields(l);
            if (f.length < 8) continue;
            raw.aps.push({ "inUse": f[0] === "*", "signal": Number(f[1]) || 0, "security": f[2] === "--" ? "" : f[2], "freq": parseInt(f[3]) || 0,
                           "channel": f[4], "rate": f[5], "bssid": f[6], "ssid": f.slice(7).join(":") });
        }
        return raw;
    }

    function band(freq) { return !freq ? "" : freq < 3000 ? "2.4 GHz" : freq < 5925 ? "5 GHz" : "6 GHz"; }
    function kindOf(sec) {
        const s = (sec || "").toUpperCase();
        if (s.indexOf("802.1X") >= 0) return "enterprise";
        if (s.indexOf("WEP") >= 0) return "wep";
        if (s.indexOf("WPA") < 0) return "open";               // none, or OWE (enhanced open)
        if (s.indexOf("WPA3") >= 0 && s.indexOf("WPA2") < 0 && s.indexOf("WPA1") < 0) return "sae";
        return "psk";
    }
    function securityLabel(sec) {
        const s = (sec || "").toUpperCase(), k = kindOf(sec);
        if (k === "open") return s.indexOf("OWE") >= 0 ? "Enhanced open" : "Open";
        if (k === "enterprise") return "Enterprise (802.1X)";
        if (k === "wep") return "WEP";
        return ["WPA1", "WPA2", "WPA3"].filter(x => s.indexOf(x) >= 0).map(x => x === "WPA1" ? "WPA" : x).join("/") + " Personal";
    }
    function kmKind(km) { return km === "sae" ? "sae" : km === "wpa-eap" ? "enterprise" : km === "none" ? "wep" : km ? "psk" : "open"; }
    function speedLabel(s) {
        const n = parseInt(s) || 0;
        return !n ? "" : n >= 1000 ? (n / 1000) + " Gb/s" : n + " Mb/s";
    }

    // The raw form (from nmcli or a fixture) → what pages read.
    function shape(raw) {
        if (!raw || !raw.devices) raw = { "wifiOn": false, "wifiHw": true, "devices": [], "show": {}, "cons": [], "aps": [], "ssids": {} };
        const ssids = raw.ssids || {};
        const wifiDev = raw.devices.find(d => d.type === "wifi") || null;
        const known = raw.cons.filter(c => c.type === "802-11-wireless").map(c => {
            const m = ssids[c.uuid] || {};
            return { "name": c.name, "uuid": c.uuid, "ssid": c.ssid || m.ssid || c.name, "hidden": !!(c.hidden || m.hidden), "kind": kmKind(c.keyMgmt || m.keyMgmt || ""),
                     "autoconnect": c.autoconnect, "active": c.active, "timestamp": c.timestamp };
        }).sort((a, b) => b.timestamp - a.timestamp);

        // Access points → one network per name: the one in use, else the strongest.
        const by = {};
        for (const ap of raw.aps) {
            if (!ap.ssid) continue;
            const n = by[ap.ssid];
            const b = band(ap.freq);
            if (!n) { by[ap.ssid] = Object.assign({}, ap, { "bands": b ? [b] : [] }); continue; }
            if (b && n.bands.indexOf(b) < 0) n.bands.push(b);
            if (ap.inUse || (!n.inUse && ap.signal > n.signal)) Object.assign(n, ap, { "bands": n.bands });
        }
        const networks = Object.keys(by).map(k => {
            const a = by[k], saved = known.find(x => x.ssid === k) || null, kind = kindOf(a.security);
            return { "ssid": k, "signal": a.signal, "secure": kind !== "open", "kind": kind, "security": securityLabel(a.security),
                     "bands": a.bands.sort(), "band": band(a.freq), "channel": a.channel, "rate": a.rate, "bssid": a.bssid, "active": a.inUse,
                     "known": !!saved, "uuid": saved ? saved.uuid : "", "autoconnect": saved ? saved.autoconnect : false };
        }).sort((a, b) => (b.active - a.active) || (b.known - a.known) || (b.signal - a.signal) || a.ssid.localeCompare(b.ssid));

        let current = null, connecting = "";
        if (wifiDev && wifiDev.uuid) {
            const con = known.find(k => k.uuid === wifiDev.uuid) || null;
            const name = con ? con.ssid : "";
            if (wifiDev.state === "connected") {
                const n = networks.find(x => x.active) || networks.find(x => x.ssid === name) || null;
                const sh = raw.show[wifiDev.device] || {};
                const v6 = (sh.ip6 || []).filter(a => !/^fe80/i.test(a));
                current = {
                    "ssid": n ? n.ssid : name, "uuid": wifiDev.uuid, "signal": n ? n.signal : 0, "security": n ? n.security : "", "kind": n ? n.kind : (con ? con.kind : ""),
                    "band": n ? n.band : "", "channel": n ? n.channel : "", "rate": n ? n.rate : "", "bssid": n ? n.bssid : "",
                    "device": wifiDev.device, "mac": sh.mac || "", "ip4": (sh.ip4 || [])[0] || "", "ip6": v6[0] || (sh.ip6 || [])[0] || "",
                    "gateway": sh.gateway || sh.gateway6 || "", "dns": sh.dns || [], "autoconnect": con ? con.autoconnect : true, "hidden": con ? con.hidden : false
                };
            } else if (wifiDev.state.indexOf("connecting") === 0) connecting = name;
        }

        const ethernet = raw.devices.filter(d => d.type === "ethernet").map(d => {
            const sh = raw.show[d.device] || {}, con = raw.cons.find(c => c.uuid === d.uuid) || null;
            return { "device": d.device, "state": d.state, "connected": d.state === "connected", "carrier": !!sh.carrier || d.state === "connected",
                     "name": con ? con.name : "", "uuid": d.uuid, "speed": speedLabel(sh.speed), "mac": sh.mac || "", "ip4": (sh.ip4 || [])[0] || "",
                     "ip6": ((sh.ip6 || []).filter(a => !/^fe80/i.test(a)))[0] || "", "gateway": sh.gateway || "", "dns": sh.dns || [] };
        });
        const vpns = raw.cons.filter(c => c.type === "vpn" || c.type === "wireguard").map(c => ({
            "name": c.name, "uuid": c.uuid, "type": c.type === "wireguard" ? "WireGuard" : (c.vpnType || "VPN"), "active": c.active,
            "state": c.state === "activated" ? "on" : c.active ? "starting" : "off"
        }));

        return { "wifiAvailable": !!wifiDev, "wifiDevice": wifiDev ? wifiDev.device : "", "wifiHardware": raw.wifiHw !== false, "wifiOn": !!raw.wifiOn && !!wifiDev,
                 "current": current, "connecting": connecting, "networks": networks, "known": known, "ethernet": ethernet, "vpns": vpns };
    }

    // ------------------------------------------------------------ fixtures

    function patch(fn) { const r = JSON.parse(JSON.stringify(fxRaw)); fn(r); fxRaw = r; }
    // A short queue of delayed fixture steps (a join takes a moment).
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

    function simulateJoin(name, password, mode, opts) {
        later(1200, () => {
            const want = (fxRaw.passwords || {})[name];
            const inRange = fxRaw.aps.some(a => a.ssid === name);
            if (!inRange && !opts.hidden) { root.joining = ""; root.joinError = root.failure(name, 10, "Error: No network with SSID '" + name + "' found."); return; }
            if (mode === "up" && fxRaw.stale && fxRaw.stale[name]) { root.joining = ""; root.joinError = root.failure(name, 4, "Error: Connection activation failed: Secrets were required, but not provided."); return; }
            if ((mode === "new" || mode === "uppw") && want !== undefined && password !== want) {
                root.joining = ""; root.joinError = root.failure(name, 4, "Error: Connection activation failed: Secrets were required, but not provided."); return;
            }
            if (opts.hidden && !inRange && (opts.kind || "psk") !== "open" && password.length < 8) {
                root.joining = ""; root.joinError = root.failure(name, 4, "Secrets were required, but not provided"); return;
            }
            root.patch(r => {
                const dev = r.devices.find(d => d.type === "wifi");
                r.cons.forEach(c => { if (c.type === "802-11-wireless") c.active = false; });
                let con = r.cons.find(c => c.type === "802-11-wireless" && (c.ssid || c.name) === name);
                if (!con) {
                    con = { "name": name, "ssid": name, "uuid": "fx-" + Date.now(), "type": "802-11-wireless", "autoconnect": true, "active": true, "state": "activated",
                            "timestamp": Math.floor(Date.now() / 1000), "hidden": !!opts.hidden, "keyMgmt": (opts.kind || "") === "open" ? "" : "wpa-psk" };
                    r.cons.push(con);
                }
                con.active = true; con.timestamp = Math.floor(Date.now() / 1000);
                if (r.stale) delete r.stale[name];
                r.aps.forEach(a => a.inUse = false);
                const ap = r.aps.filter(a => a.ssid === name).sort((a, b) => b.signal - a.signal)[0];
                if (ap) ap.inUse = true;
                else r.aps.push({ "inUse": true, "signal": 64, "security": opts.kind === "open" ? "" : "WPA2", "freq": 5180, "channel": "36", "rate": "540 Mbit/s", "bssid": "3A:4F:11:9C:02:7E", "ssid": name });
                if (dev) { dev.state = "connected"; dev.uuid = con.uuid; }
                r.show[dev.device] = Object.assign({}, r.show[dev.device], { "ip4": ["10.0.1.42/24"], "gateway": "10.0.1.1", "dns": ["10.0.1.1"], "ip6": [] });
            });
            root.joining = "";
            root.joinError = {};
        });
    }

    function setFixture(name) {
        fixture = name;
        fxRaw = name ? fixtures(name) : ({});
        joining = ""; joinError = {}; forgetting = ({}); wifiLeaving = false; leaving = ""; queue = [];
        Tailscale.setFixture(name);
        if (!name) refresh();
    }
    function fixtures(name) {
        const ap = (ssid, signal, security, freq, inUse, bssid) => ({ "inUse": !!inUse, "signal": signal, "security": security, "freq": freq,
            "channel": String(freq < 3000 ? Math.round((freq - 2407) / 5) : Math.round((freq - 5000) / 5)), "rate": freq < 3000 ? "270 Mbit/s" : "1170 Mbit/s",
            "bssid": bssid || "2E:E1:5D:CB:67:" + (10 + (signal % 89)).toString(16).toUpperCase(), "ssid": ssid });
        const con = (n, uuid, active, ts, extra) => Object.assign({ "name": n, "ssid": n, "uuid": uuid, "type": "802-11-wireless", "autoconnect": true, "active": !!active,
            "state": active ? "activated" : "", "timestamp": ts, "keyMgmt": "wpa-psk" }, extra || {});
        const wifi = (state, uuid) => ({ "device": "wlp194s0", "type": "wifi", "state": state, "uuid": uuid || "" });
        const eth = (state, uuid) => ({ "device": "enp195s0f0", "type": "ethernet", "state": state, "uuid": uuid || "" });
        const wlanShow = { "mac": "48:E7:DA:12:3B:9C", "speed": "1200 Mb/s", "carrier": false, "ip4": ["192.168.68.58/22"], "ip6": ["fe80::d094:a9e2:ec8b:b97c/64", "2800:810:4e2:1f00::1a3/64"],
                           "gateway": "192.168.68.1", "gateway6": "", "dns": ["192.168.68.1", "1.1.1.1"] };
        const ethOff = { "mac": "18:C0:4D:8E:21:F0", "speed": "", "carrier": false, "ip4": [], "ip6": [], "gateway": "", "gateway6": "", "dns": [] };

        if (name === "unavailable")
            return { "wifiOn": false, "wifiHw": true, "devices": [], "show": {}, "cons": [], "aps": [], "passwords": {} };
        if (name === "empty")
            return { "wifiOn": true, "wifiHw": true, "devices": [wifi("disconnected")], "show": { "wlp194s0": Object.assign({}, wlanShow, { "ip4": [], "ip6": [], "gateway": "", "dns": [] }) },
                     "cons": [], "aps": [], "passwords": {} };
        const normal = {
            "wifiOn": true, "wifiHw": true,
            "devices": [wifi("connected", "u-bonhart"), eth("unavailable")],
            "show": { "wlp194s0": wlanShow, "enp195s0f0": ethOff },
            "cons": [
                con("Bonhart 5G", "u-bonhart", true, 1793235319),
                con("michael-2.4", "u-michael", false, 1793100000),
                con("Oficina Monarch", "u-monarch", false, 1792000000),
                con("iPhone de Mariano", "u-iphone", false, 1791000000, { "autoconnect": false }),
                { "name": "Office WireGuard", "uuid": "u-wg", "type": "wireguard", "autoconnect": false, "active": false, "state": "", "timestamp": 0 },
                { "name": "Fibertel corporate VPN", "uuid": "u-ovpn", "type": "vpn", "vpnType": "OpenVPN", "autoconnect": false, "active": false, "state": "", "timestamp": 0 }
            ],
            "aps": [
                ap("Bonhart 5G", 82, "WPA2 WPA3", 5240, true, "20:E1:5D:CB:67:2F"), ap("Bonhart 5G", 70, "WPA2 WPA3", 2427),
                ap("michael-2.4", 77, "WPA2", 2427), ap("Fibertel WiFi843 2.4GHz", 64, "WPA2", 2437), ap("Personal Wifi Zone", 42, "", 2462),
                ap("Café Martínez", 55, "", 5180), ap("DIRECTV-HUB-5G", 38, "WPA2", 5745), ap("eduroam", 30, "WPA2 802.1X", 5200), ap("Depto 4B", 21, "WPA3", 5500)
            ],
            "passwords": { "Fibertel WiFi843 2.4GHz": "tango123", "DIRECTV-HUB-5G": "directv-5g", "Depto 4B": "cuatrobe" }
        };
        if (name === "off") {
            const r = JSON.parse(JSON.stringify(normal));
            r.wifiOn = false; r.apsOff = r.aps; r.aps = [];
            r.devices = [wifi("unavailable"), eth("unavailable")];
            r.cons.forEach(c => c.active = false);
            return r;
        }
        if (name === "stress") {
            const long = "Starbucks Guest WiFi 5GHz — Captive portal sign-in required, Torre Norte, Edificio Las Acacias";
            const r = JSON.parse(JSON.stringify(normal));
            r.devices = [wifi("connected", "u-long"), eth("connected", "u-eth"),
                         { "device": "enp0s20f0u2u1", "type": "ethernet", "state": "unavailable", "uuid": "" }];
            r.show = {
                "wlp194s0": Object.assign({}, wlanShow, { "ip6": ["2800:810:4e2:1f00:a8b2:44ff:fe19:91c3/64"], "dns": ["2800:810:4e2:1f00::1", "192.168.68.1", "1.1.1.1", "8.8.8.8", "9.9.9.9"] }),
                "enp195s0f0": { "mac": "18:C0:4D:8E:21:F0", "speed": "2500 Mb/s", "carrier": true, "ip4": ["10.10.120.244/16"], "ip6": [], "gateway": "10.10.0.1", "gateway6": "", "dns": ["10.10.0.2", "10.10.0.3"] },
                "enp0s20f0u2u1": ethOff
            };
            r.cons = [con(long, "u-long", true, 1793235319)];
            r.cons.push({ "name": "Wired connection 1 — Monarch office, third floor, desk 14 by the window", "uuid": "u-eth", "type": "802-3-ethernet", "autoconnect": true, "active": true, "state": "activated", "timestamp": 1 });
            r.aps = [ap(long, 31, "WPA1 WPA2", 5180, true)];
            const words = ["Fibertel", "Personal", "Telecentro", "Claro", "Movistar", "DIRECTV", "Starlink", "Hotel", "Biblioteca", "Departamento"];
            for (let i = 0; i < 34; i++) {
                const ssid = i % 4 === 0 ? words[i % 10] + " " + "WiFi " + (100 + i) + " — Departamento " + (i + 1) + "B Torre Norte, Edificio Las Acacias, Campana"
                                         : words[i % 10] + "-" + (1000 + i * 37).toString(16).toUpperCase();
                r.aps.push(ap(ssid, 99 - i * 3 > 5 ? 99 - i * 3 : 7, ["WPA2", "", "WPA2 WPA3", "WPA3", "WPA2 802.1X", "WEP"][i % 6], i % 3 ? 5180 + i * 20 : 2412 + (i % 11) * 5));
                if (i % 5 === 0) r.cons.push(con(ssid, "u-s" + i, false, 1793000000 - i));
            }
            for (let i = 0; i < 6; i++) r.cons.push(con("Saved network far away " + (i + 1) + " — Aeropuerto Internacional Ministro Pistarini, Terminal A, Gate " + (i + 12),
                                                         "u-far" + i, false, 1780000000 - i));
            for (let i = 0; i < 4; i++) r.cons.push({ "name": "Corporate VPN " + (i + 1) + " — Monarch MD production cluster, us-east-1, read-only bastion access", "uuid": "u-v" + i,
                                                       "type": i % 2 ? "vpn" : "wireguard", "vpnType": "OpenVPN", "autoconnect": false, "active": i === 1, "state": i === 1 ? "activated" : "", "timestamp": 0 });
            r.passwords = {};
            r.stale = {};
            r.stale[r.aps[1].ssid] = true;
            return r;
        }
        return normal;
    }

    // ------------------------------------------------------------------ IPC

    IpcHandler {
        target: "network"
        // normal | stress | empty | off | unavailable, or "" for live.
        function fixture(name: string): void { root.setFixture(name === "live" ? "" : name); }
        // What a click on a network does in the sidebar: join, or open
        // Settings › Network at it to ask for the password.
        function join(name: string): void { if (!root.join(name, "", {})) root.ask(name); }
        function hidden(): void { root.askHidden(); }
        function forget(name: string): void { const k = root.known.find(x => x.ssid === name); if (k) root.forget(k.uuid, k.ssid); }
        function wifi(on: bool): void { if (on) root.setWifi(true); else root.turnWifiOff(); }
        function disconnect(): void { root.disconnectSoon(); }
        function tailscale(on: bool): void { if (on) Tailscale.setOn(true); else Tailscale.turnOffSoon(); }
        function scan(): void { root.scan(); }
        function state(): string {
            return JSON.stringify({ "fixture": root.fixture, "scanning": root.scanning, "queue": root.queue.length, "wifiOn": root.wifiOn, "current": root.ssid, "joining": root.joining, "error": root.joinError,
                                    "networks": root.networks.length, "known": root.known.length, "forgetting": Object.keys(root.forgetting) });
        }
    }
}
