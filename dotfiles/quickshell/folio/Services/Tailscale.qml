pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Tailscale through its CLI: on while the backend is Running. setOn() runs
// `tailscale up/down`, which works without sudo only when this user is the
// operator (`tailscale set --operator=$USER`); otherwise canToggle is false.
// In the harness the command is only recorded (Sys.run). Network's fixtures
// set this one's too (setFixture), so the Network page shows every state.
Singleton {
    id: root

    property bool available: false      // the CLI answered
    property string state: ""           // BackendState: Running, Stopped, NeedsLogin...
    property string tailnet: ""
    property string dnsName: ""         // this machine on the tailnet
    property var ips: []                // this machine's Tailscale addresses, IPv4 first
    property var exitNode: null         // {name, online} while traffic leaves through a peer
    property int exitNodeOptions: 0     // peers offering to be one
    property int peersOnline: 0
    property int peers: 0
    property bool canToggle: false
    property bool busy: false
    property bool leaving: false        // off, waiting on its undo toast
    property int toast: 0
    readonly property bool on: state === "Running"
    readonly property string summary: !available ? "" : on ? (peersOnline > 0 ? peersOnline + (peersOnline === 1 ? " peer" : " peers") : "Connected") : state === "NeedsLogin" ? "Signed out" : "Off"

    property string fixture: ""
    readonly property bool fake: fixture !== ""

    function refresh() { if (!fake && !status.running) status.running = true; }
    function setOn(v) {
        leaving = false;
        if (toast) { Toasts.take(toast); toast = 0; }
        if (fake) { apply(Object.assign({}, fixtures(fixture), { "state": v ? "Running" : "Stopped" }, v ? {} : { "exitNode": null, "peersOnline": 0 })); return; }
        if (!canToggle || busy) return;
        const cmd = ["tailscale", v ? "up" : "down"];
        if (Sys.harness) { Sys.run(cmd); return; }
        busy = true;
        state = v ? "Starting" : "Stopped";
        toggler.command = cmd;
        toggler.running = true;
    }
    // Off waits on an undo toast: this laptop is reached over Tailscale, and
    // a stray tap should not cut the line.
    function turnOffSoon() {
        if (!on || leaving) return;
        leaving = true;
        toast = Toasts.undo("Tailscale turns off", () => { root.toast = 0; if (root.leaving) root.setOn(false); },
                            () => { root.toast = 0; root.leaving = false; }, "shield");
    }

    Process {
        id: status
        command: ["sh", "-c", "command -v tailscale >/dev/null && exec tailscale status --json"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.fake) return;
                let d;
                try { d = JSON.parse(text); } catch (e) { root.available = false; return; }
                const peers = Object.values(d.Peer || {});
                const exit = peers.find(p => p.ExitNode) || null;
                const self = d.Self || {};
                root.apply({
                    "available": true, "state": root.busy ? root.state : (d.BackendState || ""),
                    "tailnet": (d.CurrentTailnet && d.CurrentTailnet.Name) || "",
                    "dnsName": (self.DNSName || "").replace(/\.$/, ""),
                    "ips": (self.TailscaleIPs || d.TailscaleIPs || []).slice().sort((a, b) => (a.indexOf(":") >= 0) - (b.indexOf(":") >= 0)),
                    "exitNode": exit ? { "name": (exit.DNSName || exit.HostName || "").split(".")[0] || exit.HostName, "online": !!exit.Online } : null,
                    "exitNodeOptions": peers.filter(p => p.ExitNodeOption).length,
                    "peersOnline": peers.filter(p => p.Online).length, "peers": peers.length
                });
            }
        }
    }
    function apply(v) {
        available = v.available; state = v.state; tailnet = v.tailnet || ""; dnsName = v.dnsName || ""; ips = v.ips || [];
        exitNode = v.exitNode || null; exitNodeOptions = v.exitNodeOptions || 0; peersOnline = v.peersOnline || 0; peers = v.peers || 0;
        if (v.canToggle !== undefined) canToggle = v.canToggle;
    }
    // Whether this user may run up/down: the operator in the daemon's prefs.
    Process {
        id: prefs
        running: true
        command: ["sh", "-c", "command -v tailscale >/dev/null && exec tailscale debug prefs"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.fake) return;
                try { root.canToggle = JSON.parse(text).OperatorUser === Quickshell.env("USER"); } catch (e) { root.canToggle = false; }
            }
        }
    }
    Process {
        id: toggler
        onExited: { root.busy = false; root.refresh(); }
    }

    Timer { interval: 30000; running: !root.fake; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

    // ------------------------------------------------------------ fixtures

    function setFixture(name) {
        fixture = name || "";
        leaving = false;
        if (fake) apply(fixtures(fixture));
        else { prefs.running = true; refresh(); }
    }
    function fixtures(name) {
        const base = { "available": true, "state": "Running", "tailnet": "marianomiguel.com", "dnsName": "bonhart-3.taile97d70.ts.net",
                       "ips": ["100.71.230.32", "fd7a:115c:a1e0::5232:e621"], "exitNode": null, "exitNodeOptions": 1, "peersOnline": 3, "peers": 6, "canToggle": true };
        if (name === "stress")
            return Object.assign(base, { "tailnet": "monarch-medical-devices-engineering-and-operations.org.github", "dnsName": "bonhart-3-the-laptop-on-the-desk-by-the-window-in-the-third-floor.taile97d70.ts.net",
                                         "exitNode": { "name": "exit-node-sao-paulo-brazil-aws-sa-east-1-primary-with-a-very-long-hostname-indeed", "online": true },
                                         "exitNodeOptions": 14, "peersOnline": 214, "peers": 380 });
        if (name === "off") return Object.assign(base, { "state": "Stopped", "peersOnline": 0 });
        if (name === "empty") return Object.assign(base, { "state": "NeedsLogin", "tailnet": "", "dnsName": "", "ips": [], "peersOnline": 0, "peers": 0, "exitNodeOptions": 0 });
        if (name === "unavailable") return Object.assign(base, { "available": false, "state": "" });
        return base;
    }
}
