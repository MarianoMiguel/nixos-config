import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services

// The lock screen: an ext-session-lock bound to Session.locked. The focused
// screen gets the whole page (LockPage), the others the plate alone. One
// password buffer serves every screen, so typing works wherever the keyboard
// lands. Unlocking plays the page out (LockPage) and releases the lock on a
// timer of its own, so the lock always ends even if a frame never draws.
// The page lists the notifications that are waiting (LockNotes), with their
// text only when "lock.previews" is "always".
Scope {
    id: root

    readonly property bool harness: (Quickshell.env("FOLIO_HARNESS") || "") !== ""

    // typing | checking | opening
    property string phase: "typing"
    property string buffer: ""
    property int lifting: -1                // cells still printed after a refusal
    readonly property int shown: lifting >= 0 ? lifting : buffer.length
    property string message: ""
    property bool messageError: false
    property bool peek: false
    property string mainScreen: ""
    property var fx: null                   // fixture data in place of the live status
    property string userName: Quickshell.env("USER") || ""

    signal refused()
    signal powerChoices()                   // show Hibernate / Shut down (IPC)

    // Waiting notifications, grouped by app (Notifs.groups: newest app first,
    // apps switched off already left out), as plain data for the page.
    // Previews are off unless the preference says "always": a screen left
    // locked shows only which apps are waiting and how many.
    property string previewsForced: ""      // always | never: a test's override
    readonly property bool previews: (previewsForced || Settings.get("lock.previews") || "never") === "always"
    property string notesOpen: ""           // the app whose slip is open
    property real now: Date.now()           // ticks the "ago" labels
    Timer { interval: 30000; repeat: true; running: Session.locked; onTriggered: root.now = Date.now() }
    readonly property var notes: fx ? (fx.notes || []) : Notifs.groups.map(g => root.toGroup(g))
    readonly property string notesQuiet: fx ? (fx.quiet || "") : Notifs.quietReason
    function toGroup(g) {
        root.now;
        const app = Notifs.prefs.apps[g.app] || {};
        return {
            "app": g.app, "icon": app.icon || g.icon, "count": g.items.length, "ago": Notifs.ago(g.items[0]),
            "items": g.items.slice(0, 3).map(n => ({ "summary": n.summary || "", "body": n.body || "", "ago": Notifs.ago(n) }))
        };
    }
    // The arrow keys open the next or previous slip (with previews on).
    function step(by) {
        if (!previews || notes.length === 0) return;
        const at = notes.findIndex(g => g.app === notesOpen);
        const next = at + by;
        notesOpen = next < 0 ? "" : notes[Math.min(notes.length - 1, next)].app;
    }

    // Sounds (Services/Sounds) when the screen locks and when it opens.
    function sound(name) { Sounds.play(name); }

    Connections {
        target: Session
        function onLockedChanged() {
            marker.setText(Session.locked ? "locked\n" : "");
            if (Session.locked) { root.sound("lock"); root.begin(); } else root.end();
        }
    }
    Component.onCompleted: if (Session.locked) begin()

    // A shell that dies while locked leaves the compositor locked with nobody
    // to unlock it. The lock is written down in the runtime directory, and a
    // restarted shell (systemd restarts it) locks again at once: fail closed,
    // and the password still opens it.
    FileView {
        id: marker
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/folio-locked"
        printErrors: false
        onLoaded: if (text().trim() === "locked" && !Session.locked) Session.lock()
    }

    function begin() {
        releaseTimer.stop();
        phase = "typing";
        buffer = "";
        lifting = -1;
        message = "";
        messageError = false;
        peek = false;
        const s = Shell.screenFor(Quickshell.screens);
        mainScreen = s ? s.name : "";
        failures = 0;
        notesOpen = "";
        now = Date.now();
        secureWatch.restart();
    }
    function end() {
        if (phase !== "opening") sound("unlock");   // opened from outside (loginctl)
        releaseTimer.stop();
        secureWatch.stop();
        phase = "typing";
        buffer = "";
        lifting = -1;
        peek = false;
        fx = null;
        notesOpen = "";
        Fingerprint.forced = null;
    }

    function key(event) {
        const k = event.key;
        if (k === Qt.Key_Down || k === Qt.Key_Up) { if (phase !== "opening") step(k === Qt.Key_Down ? 1 : -1); return; }
        if (phase !== "typing") return;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) { submit(); return; }
        if (k === Qt.Key_Escape || (k === Qt.Key_Backspace && (event.modifiers & Qt.ControlModifier))) { type(""); return; }
        if (k === Qt.Key_Backspace) { type(buffer.slice(0, -1)); return; }
        if (event.modifiers & Qt.ControlModifier) return;
        const t = event.text;
        if (t && t.length > 0 && t.charCodeAt(0) >= 32 && t !== "\u007f") type((buffer + t).slice(0, 256));
    }
    function type(value) {
        liftTimer.stop();
        lifting = -1;
        buffer = value;
        if (messageError) { message = ""; messageError = false; }
    }
    function submit() {
        if (phase !== "typing" || buffer.length === 0) return;
        phase = "checking";
        message = "";
        messageError = false;
        authority.check(buffer);
    }
    function accept() {
        if (phase === "opening" || !Session.locked) return;
        phase = "opening";
        sound("unlock");
        liftTimer.stop();
        lifting = -1;
        buffer = "";
        peek = false;
        message = "";
        authority.stop();
        releaseTimer.restart();
    }
    function refuse(text) {
        if (phase === "opening") return;
        phase = "typing";
        lifting = buffer.length;
        buffer = "";
        message = text;
        messageError = true;
        refused();
        liftTimer.interval = Math.max(1, 420 * Theme.motion);
        liftTimer.restart();
    }
    // After a refusal the cells lift one by one, last first.
    Timer {
        id: liftTimer
        repeat: true
        onTriggered: {
            interval = Math.max(1, 28 * Theme.motion);
            root.lifting = Math.max(0, root.lifting - 1);
            if (root.lifting === 0) { root.lifting = -1; stop(); }
        }
    }
    // The page plays out (LockPage), then the lock lets go.
    Timer {
        id: releaseTimer
        interval: Math.max(80, 1450 * Theme.motion)
        onTriggered: Session.unlock()
    }

    Auth {
        id: authority
        active: Session.locked && sessionLock.secure
        onAccepted: root.accept()
        onRefused: message => root.refuse(message)
        onNotice: message => { root.message = message; root.messageError = false; }
    }

    // The user's name from the passwd entry.
    Process {
        running: true
        command: ["sh", "-c", "getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1"]
        stdout: StdioCollector { onStreamFinished: if (text.trim()) root.userName = text.trim() }
    }

    // If the compositor refuses or drops the lock, ask again a few times; a
    // lock that cannot be had is not pretended.
    property bool retrying: false
    property int failures: 0
    Timer { id: retryTimer; interval: 1000; onTriggered: { root.retrying = false; secureWatch.restart(); } }
    Timer { id: secureWatch; interval: 3000; onTriggered: root.lockLost() }
    function lockLost() {
        if (!Session.locked || sessionLock.secure || retrying) return;
        if (++failures > 3) {
            console.warn("Lock: the compositor refused the session lock");
            Session.unlock();
            return;
        }
        retrying = true;
        retryTimer.restart();
    }

    WlSessionLock {
        id: sessionLock
        locked: Session.locked && !root.retrying
        onSecureStateChanged: if (secure) secureWatch.stop(); else root.lockLost()

        WlSessionLockSurface {
            id: surface
            color: Theme.paper
            readonly property bool isMain: {
                const names = Quickshell.screens.map(s => s.name);
                const main = names.indexOf(root.mainScreen) >= 0 ? root.mainScreen : (names[0] || "");
                return !screen || screen.name === main;
            }
            LockPage {
                anchors.fill: parent
                lock: root
                auth: authority
                main: surface.isMain
            }
        }
    }

    // Fixtures: the lock with made-up status, for the harness.
    readonly property var fixtures: ({
        "normal": { "name": "Mariano", "ssid": "Bonhart 5G", "battery": 84, "layout": "US", "title": "Libertango", "artist": "Astor Piazzolla", "playing": true, "fingerprint": true, "notes": fixtureNotes("normal") },
        "stress": { "name": "Mariano Miguel de los Santos Echeverría Uriarte Fernández de la Torre y Montenegro", "ssid": "Departamento 4B — Red de invitados de la oficina central, piso 12, ala norte (5 GHz)", "battery": 100, "layout": "ES", "title": "Adiós Nonino (Live at the Teatro Colón, Buenos Aires — 40th Anniversary Remaster, Extended Version)", "artist": "Astor Piazzolla y su Quinteto Tango Nuevo con la Orquesta Filarmónica de Buenos Aires", "playing": false, "fingerprint": true, "typed": "correct horse battery staple", "message": "The account is locked due to 3 failed logins. (2 minutes left to unlock.) Please wait before trying again, or ask an administrator.", "notes": fixtureNotes("stress"), "quiet": "dnd" },
        "empty": { "name": "", "ssid": "", "battery": -1, "layout": "", "title": "", "artist": "", "playing": false, "fingerprint": false, "notes": [] }
    })
    function fixtureNotes(name) {
        const g = (app, icon, ago, items, count) => ({ "app": app, "icon": icon, "ago": ago, "count": count || items.length, "items": items.map(i => ({ "summary": i[0], "body": i[1], "ago": i[2] || ago })) });
        if (name === "normal") return [
            g("Slack", "slack", "now", [
                ["Ana Pérez", "¿Podés mirar el deploy antes de las 15? Quedó trabado en staging desde anoche."],
                ["#infra-alerts", "Build 4812 passed on main · 6 min 12 s", "4 min"],
                ["Juan Ignacio", "dale, lo vemos mañana", "18 min"]
            ]),
            g("Calendar", "org.gnome.Calendar", "12 min", [["Standup in 10 minutes", "Google Meet · Monarch Engineering"]]),
            g("Telegram Desktop", "telegram", "1 h", [
                ["Mamá", "¿Venís el domingo? Hago empanadas 🥟"],
                ["Mamá", "Avisame así compro", "58 min"]
            ])
        ];
        if (name !== "stress") return [];
        const long = "Slack — #infra-alerts-production-eu-west-1-critical (Monarch Health Engineering workspace)";
        const body = "Deploy 4812 to production-eu-west-1 failed health checks on 14 of 32 instances; rolling back automatically. Error budget for this month is now at 3 %, and the on-call rotation has been paged twice in the last hour.";
        const out = [g(long, "slack", "now", [
            ["PagerDuty · CRITICAL · api-gateway p99 latency above 4 s for 15 minutes (eu-west-1, eu-central-1, us-east-2)", body],
            ["Build 4813 failed on main", "tests/integration/test_claims_reconciliation.py::test_retry_after_partial_settlement — AssertionError", "1 min"],
            ["Ana Pérez", "estoy mirando", "1 min"]
        ], 1312)];
        const apps = [["Google Chrome", "google-chrome"], ["Telegram Desktop", "telegram"], ["Calendar", "org.gnome.Calendar"], ["Beeper", "beepertexts"], ["Signal", "signal-desktop"], ["Thunderbird", "thunderbird"], ["Discord", "discord"], ["Spotify", "spotify"], ["Visual Studio Code", "code"], ["Tailscale", "tailscale"], ["notify-send", ""], ["Steam", "steam"]];
        for (let i = 0; i < apps.length; i++)
            out.push(g(apps[i][0], apps[i][1], (i + 1) * 7 + " min", [[i % 3 === 0 ? "A ninety-character title that keeps going so the slip has to elide it at its right edge" : "Message " + (i + 1), i % 2 === 0 ? body : "Short."]], i % 4 === 0 ? 120 + i : i % 4 + 1));
        return out;
    }

    IpcHandler {
        target: "lock"
        function lock(): void { Session.lock(); }
        function isLocked(): bool { return sessionLock.secure; }
        function fixture(name: string): void {
            const f = root.fixtures[name] || null;
            root.fx = f;
            Fingerprint.forced = f ? f.fingerprint : null;
            const was = Session.locked;
            Session.lock();
            if (was) root.begin();
            if (!f) return;
            if (f.typed) root.buffer = f.typed;
            if (f.message) { root.message = f.message; root.messageError = true; }
        }
        // Notification previews for this lock: always | never ("" follows lock.previews).
        function previews(mode: string): void { root.previewsForced = mode === "always" || mode === "never" ? mode : ""; }
        // Open an app's slip by its place in the list (-1 closes).
        function open(index: int): void { const g = root.notes[index]; root.notesOpen = g ? g.app : ""; }
        // Harness only: a fingerprint match.
        function touch(): void { if (root.harness && Session.locked) root.accept(); }
        function peek(on: bool): void { root.peek = on; }
        // The power choices, as holding the power tab offers them.
        function power(): void { if (Session.locked) root.powerChoices(); }
    }
}
