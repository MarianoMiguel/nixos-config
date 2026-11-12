import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services

// The island: one deep-ink pill at the top of every screen that morphs into
// whatever is happening. This file decides what that is; IslandWindow draws
// it. Transient flashes (level, note, battery, layout) win over the resting
// face: the player if open, else recording, focus, music, then the clock.
Scope {
    id: root

    // ------------------------------------------------------------ test data
    // fixture() pins fake data; show() pins a face. Neither touches services.
    property var fx: null
    property string forced: ""
    readonly property var fixtures: ({
        "normal": {
            "media": { "title": "Libertango", "artist": "Astor Piazzolla", "art": "", "playing": true, "position": 82, "length": 231, "device": "AirPods Pro", "bluetooth": true },
            "focus": { "clock": "24:12", "progress": 0.03 },
            "recording": 72,
            "note": { "sender": "Lucía", "text": "¿Mate a las cinco? Llevo facturas.", "image": "", "icon": "" },
            "level": { "kind": "volume", "value": 0.64, "muted": false },
            "battery": 8,
            "layout": "English (US)"
        },
        "stress": {
            "media": {
                "title": "Adiós Nonino (Live at the Teatro Colón, Buenos Aires — 40th Anniversary Remaster, Extended)",
                "artist": "Astor Piazzolla y su Quinteto Nuevo Tango with the Orquesta Filarmónica de Buenos Aires",
                "art": "", "playing": true, "position": 3725, "length": 5412,
                "device": "Family 17h/19h HD Audio Controller Speaker + Headphones", "bluetooth": false
            },
            "focus": { "clock": "119:59", "progress": 0.92 },
            "recording": 3725,
            "note": {
                "sender": "Slack — #infra-alerts-production-eu-west-1-critical", "image": "", "icon": "",
                "text": "[FIRING:3] KubePodCrashLooping production/payments-api-7d9f8b6c5d-x2k9q container payments-api is restarting"
            },
            "level": { "kind": "volume", "value": 1, "muted": false },
            "battery": 6,
            "layout": "Spanish (Latin American, dead keys, with Euro on 5 and the Apple layout)"
        },
        "empty": {
            "media": null,
            "focus": { "clock": "25:00", "progress": 0 },
            "recording": 0,
            "note": { "sender": "", "text": "", "image": "", "icon": "" },
            "level": { "kind": "volume", "value": 0, "muted": true },
            "battery": 100,
            "layout": ""
        }
    })

    // ------------------------------------------------------------ data
    readonly property var fm: fx ? fx.media : null
    readonly property bool mediaActive: fx ? !!fm : Media.active
    readonly property string title: fm ? fm.title : Media.title
    readonly property string artist: fm ? fm.artist : Media.artist
    readonly property string art: fm ? fm.art : Media.art
    readonly property bool playing: fm ? fm.playing : Media.playing
    readonly property real position: fm ? fm.position : Media.position
    readonly property real length: fm ? fm.length : Media.length
    readonly property string device: fm ? fm.device : Audio.device
    readonly property bool deviceBluetooth: fm ? fm.bluetooth : !!(Audio.sink && /^bluez/.test(Audio.sink.name || ""))

    property bool recLive: false
    property real recSince: 0
    property real now: Date.now()
    readonly property bool recording: fx ? forced === "recording" : recLive
    readonly property int recSeconds: fx ? fx.recording : Math.max(0, Math.floor((now - recSince) / 1000))
    readonly property bool focusActive: fx ? forced === "focus" : Focus.active
    readonly property string focusClock: fx ? fx.focus.clock : Focus.clock
    readonly property real focusProgress: fx ? fx.focus.progress : Focus.progress

    // ------------------------------------------------------------ faces
    property string flash: ""
    property var payload: ({})
    property string playerScreen: ""
    property bool hoveringPlayer: false
    readonly property bool playerOpen: Shell.playerOpen && mediaActive
    // Settings island.live off keeps the island to the clock and flashes.
    readonly property bool live: Settings.get("island.live") !== false || fx !== null
    readonly property string resting: forced !== "" && forced !== "player" ? forced
        : !live ? "idle" : recording ? "recording" : focusActive ? "focus" : mediaActive ? "music" : "idle"

    // What one screen's island shows.
    function faceFor(output) {
        const mine = playerOpen && output === playerScreen;
        if (flash !== "" && !(mine && hoveringPlayer)) return flash;
        return mine ? "player" : resting;
    }

    // A transient face: shows on every screen, then gives way.
    function show(name, data, ms) {
        if (Shell.playerOpen && hoveringPlayer) return;     // never pull the player from under the pointer
        payload = data || {};
        flash = name;
        flashTimer.interval = ms;
        flashTimer.restart();
    }
    function endFlash() { flashTimer.stop(); flash = ""; }
    Timer { id: flashTimer; onTriggered: root.flash = "" }

    // ------------------------------------------------------------ actions
    function openPlayer(output) {
        if (!mediaActive) return;
        playerScreen = output;
        endFlash();
        if (!Shell.playerOpen) Shell.togglePlayer();
    }
    function closePlayer() { if (Shell.playerOpen) Shell.playerOpen = false; hoveringPlayer = false; }
    function toggle() { if (fm) fx = Object.assign({}, fx, { "media": Object.assign({}, fm, { "playing": !fm.playing }) }); else Media.toggle(); }
    function next() { if (!fm) Media.next(); }
    function previous() { if (!fm) Media.previous(); }
    function seek(seconds) { if (fm) fx = Object.assign({}, fx, { "media": Object.assign({}, fm, { "position": seconds }) }); else Media.seek(seconds); }
    function stopRecording() { if (fx) { forced = ""; return; } Quickshell.execDetached(["mariano-capture", "video-toggle"]); }
    function openNotifications() { endFlash(); Shell.toggleSidebar("notifications"); }

    onMediaActiveChanged: if (!mediaActive) closePlayer()
    Connections {
        target: Shell
        function onPlayerOpenChanged() {
            if (!Shell.playerOpen) { root.hoveringPlayer = false; return; }
            if (root.playerScreen === "" || !Quickshell.screens.some(s => s.name === root.playerScreen)) {
                const s = Shell.screenFor(Quickshell.screens);
                root.playerScreen = s ? s.name : "";
            }
        }
    }

    // ------------------------------------------------------------ events
    // Startup sets every value once; only later changes are events.
    property bool armed: false
    Timer { running: true; interval: 3000; onTriggered: root.armed = true }

    function level(kind) {
        if (kind === "brightness") return { "kind": kind, "value": Brightness.level, "muted": false };
        if (kind === "mic") return { "kind": kind, "value": Audio.source && Audio.source.audio ? Audio.source.audio.volume : 0, "muted": Audio.micMuted };
        return { "kind": "volume", "value": Audio.volume, "muted": Audio.muted };
    }
    Connections {
        target: Audio
        function onChanged(kind) { root.show("level", { "kind": kind, "live": true }, 1400); }
    }
    Connections {
        target: Brightness
        function onChanged() { root.show("level", { "kind": "brightness", "live": true }, 1400); }
    }
    Connections {
        target: Notifs
        function onPosted(n) {
            if (Shell.sidebarOpen || root.fx) return;       // the sidebar already shows it
            const body = (n.body || "").replace(/\s+/g, " ").trim();
            const summary = (n.summary || "").replace(/\s+/g, " ").trim();
            root.show("note", {
                "sender": body ? summary : (n.appName || "Notification"),
                "text": body || summary,
                "image": n.image || "",
                "icon": n.appIcon ? Quickshell.iconPath(n.appIcon, true) : ""
            }, 2600);
        }
    }
    Connections {
        target: Battery
        function onLowChanged() { if (root.armed && Battery.low && !root.fx) root.show("battery", { "kind": "low", "percent": Battery.percent }, 2600); }
        function onCriticalChanged() { if (root.armed && Battery.critical && !root.fx) root.show("battery", { "kind": "low", "percent": Battery.percent }, 2600); }
        function onChargingChanged() { if (root.armed && Battery.charging && !root.fx) root.show("battery", { "kind": "charging", "percent": Battery.percent }, 2200); }
        function onFullChanged() { if (root.armed && Battery.full && !root.fx) root.show("battery", { "kind": "full", "percent": 100 }, 2200); }
    }
    Connections {
        target: Niri
        function onLayoutNameChanged() { if (root.armed && Niri.layoutName && !root.fx) root.show("layout", { "name": Niri.layoutName }, 1200); }
    }

    // The screen recorder (scripts/capture.sh) runs as a user unit.
    Process {
        id: recPoll
        command: ["systemctl", "--user", "show", "--timestamp=unix", "-p", "ActiveState", "-p", "ActiveEnterTimestamp", "mariano-capture-video.service"]
        stdout: StdioCollector {
            onStreamFinished: {
                const state = (text.match(/ActiveState=(\S+)/) || [])[1] || "";
                const since = Number((text.match(/ActiveEnterTimestamp=@(\d+)/) || [])[1] || 0);
                root.recLive = state === "active" || state === "activating";
                root.recSince = !root.recLive ? 0 : since > 0 ? since * 1000 : (root.recSince || Date.now());
                root.now = Date.now();
            }
        }
        onExited: if (root.recAgain) { root.recAgain = false; running = true; }
    }
    // The recorder says when it starts and stops (scripts/capture.sh calls
    // recordingChanged), so the unit is read only then, once at start (a
    // recording that outlived a shell restart), and every 30 s while one
    // runs, in case a stop went unheard. No polling the rest of the time.
    property bool recAgain: false
    function recCheck() { if (recPoll.running) recAgain = true; else recPoll.running = true; }
    Timer { interval: 2000; running: true; triggeredOnStart: true; onTriggered: root.recCheck() }
    Timer { interval: 30000; running: root.recLive && !root.fx; repeat: true; onTriggered: root.recCheck() }
    Timer { interval: 1000; running: root.recLive && !root.fx; repeat: true; onTriggered: root.now = Date.now() }

    // ------------------------------------------------------------ IPC
    IpcHandler {
        target: "island"
        // The screen recorder started or stopped (scripts/capture.sh).
        function recordingChanged(): void { root.recCheck(); }
        // normal | stress | empty; anything else (live) returns to real data.
        function fixture(name: string): void {
            root.endFlash();
            root.forced = "";
            root.closePlayer();
            root.fx = root.fixtures[name] ? JSON.parse(JSON.stringify(root.fixtures[name])) : null;
            if (name === "stress" || name === "empty") flashLater.restart();   // battery low / charged
        }
        // idle | music | player | focus | recording | level | mic | brightness
        // | note | battery | charging | full | layout | auto (back to the rules).
        // Faces that need data take the normal fixture's when none is set;
        // level, mic and brightness then read the real values (read only).
        // From the CLI: qs ipc call -- island show player.
        function show(face: string): void {
            const f = root.fx || root.fixtures.normal;
            if (!root.fx && ["idle", "auto", "level", "mic", "brightness", "layout"].indexOf(face) < 0)
                root.fx = JSON.parse(JSON.stringify(root.fixtures.normal));
            root.endFlash();
            flashLater.stop();
            if (face === "auto") { root.forced = ""; return; }
            if (["idle", "music", "focus", "recording"].indexOf(face) >= 0) { root.closePlayer(); root.forced = face; return; }
            root.forced = "";
            if (face === "player") { const s = Shell.screenFor(Quickshell.screens); root.openPlayer(s ? s.name : ""); return; }
            if (face === "level" || face === "mic" || face === "brightness") {
                const kind = face === "level" ? "volume" : face;
                root.show("level", root.fx ? Object.assign({}, root.fx.level, { "kind": kind }) : { "kind": kind, "live": true }, 1400);
            }
            else if (face === "note") root.show("note", f.note, 2600);
            else if (face === "battery") root.show("battery", { "kind": "low", "percent": f.battery }, 2600);
            else if (face === "charging") root.show("battery", { "kind": "charging", "percent": f.battery }, 2200);
            else if (face === "full") root.show("battery", { "kind": "full", "percent": 100 }, 2200);
            else if (face === "layout") root.show("layout", { "name": f.layout || Niri.layoutName || "English (US)" }, 1200);
        }
        // Keep the current transient face up that many seconds (screenshots).
        function hold(seconds: int): void { if (root.flash) { flashTimer.interval = Math.max(1, seconds) * 1000; flashTimer.restart(); } }
    }
    Timer {
        id: flashLater
        interval: 600
        onTriggered: {
            if (!root.fx) return;
            if (root.fx.battery <= 10) root.show("battery", { "kind": "low", "percent": root.fx.battery }, 2600);
            else if (root.fx.battery >= 100) root.show("battery", { "kind": "full", "percent": 100 }, 2200);
        }
    }

    // Volume, microphone and brightness keys (niri binds call these).
    IpcHandler {
        target: "osd"
        function volumeUp(): void { Audio.step(0.05); Sounds.play("volume"); }
        function volumeDown(): void { Audio.step(-0.05); Sounds.play("volume"); }
        function mute(): void { Audio.toggleMute(); }
        function micMute(): void { Audio.toggleMic(); }
        function brightnessUp(): void { if (Brightness.available) Brightness.step(0.05); }
        function brightnessDown(): void { if (Brightness.available) Brightness.step(-0.05); }
    }

    Variants {
        model: Quickshell.screens
        Scope {
            id: perScreen
            required property var modelData
            IslandWindow { screen: perScreen.modelData; hub: root }
            // While the player is open, a click anywhere else closes it.
            PanelWindow {
                screen: perScreen.modelData
                visible: root.faceFor(perScreen.modelData.name) === "player"
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.namespace: "folio:island-catch"
                exclusionMode: ExclusionMode.Ignore
                anchors { top: true; bottom: true; left: true; right: true }
                color: "transparent"
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onPressed: root.closePlayer()
                }
            }
        }
    }
}
