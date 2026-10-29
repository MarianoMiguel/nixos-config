import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services

// Folio's login screen (greetd). Every screen gets the whole page, so the
// screen a KVM captures always has the password on it; one password buffer
// serves them all. Keyboard first: type the password and press Enter; Tab
// moves to the user (when there are several), the session and power, the
// arrows change them, Escape comes back and clears. A pointer works too.
//
// What it reads (modules/nixos/folio-greeter.nix sets these):
//   FOLIO_GREETER_SESSIONS        colon-separated folders of *.desktop sessions
//   FOLIO_GREETER_DEFAULT_SESSION the session chosen first (niri)
//   FOLIO_GREETER_USER            the user chosen first
//   FOLIO_GREETER_STATE           where "launched" is written just before a
//                                 session starts (the wrapper falls back to
//                                 DMS's greeter when it is missing)
// Folio's mode, ink and plate come from Theme, which reads the selection
// azure-folio publishes world-readable (the wrapper points HOME at it).
Scope {
    id: root

    readonly property bool harness: (Quickshell.env("FOLIO_HARNESS") || "") !== ""

    // typing | opening | launching
    property string phase: "typing"
    property string buffer: ""
    property int lifting: -1
    readonly property int shown: lifting >= 0 ? lifting : buffer.length
    property string message: ""
    property bool messageError: false
    property bool peek: false
    // password | user | session | power
    property string focusPart: "password"
    property var fx: null                   // a fixture in place of the live system

    signal refused()

    // ------------------------------------------------------------ users
    property var liveUsers: []
    readonly property var users: fx && fx.users ? fx.users : liveUsers
    property int userIndex: 0
    readonly property var user: users[Math.min(userIndex, users.length - 1)] || ({ "name": Quickshell.env("FOLIO_GREETER_USER") || "", "real": "", "avatar": "" })
    Process {
        running: true
        command: ["sh", "-c", `getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ { print $1 "\\t" $5 }' | while IFS="$(printf '\\t')" read -r n g; do
            a=/var/lib/AccountsService/icons/$n; [ -r "$a" ] || a=""
            printf '%s\\t%s\\t%s\\n' "$n" "\${g%%,*}" "$a"; done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.split("\n").filter(l => l).map(l => { const f = l.split("\t"); return { "name": f[0], "real": f[1] || "", "avatar": f[2] || "" }; });
                root.liveUsers = list;
                const want = Quickshell.env("FOLIO_GREETER_USER") || "";
                root.userIndex = Math.max(0, list.findIndex(u => u.name === want));
                root.ensureBegun();
            }
        }
    }
    // Start the conversation for the chosen user (again, if the list changed
    // who that is), so a finger works before anything is typed.
    function ensureBegun() {
        if (fx || phase !== "typing" || !user.name) return;
        if (!login.active || login.user !== user.name) login.begin(user.name);
    }
    Timer { running: true; interval: 1500; onTriggered: root.ensureBegun() }
    function chooseUser(i) {
        if (users.length < 2 || phase !== "typing") return;
        userIndex = (i + users.length) % users.length;
        clearEntry();
        login.begin(user.name);
    }

    // ------------------------------------------------------------ sessions
    property var liveSessions: []
    property bool sessionsRead: false
    readonly property var sessions: fx && fx.sessions ? fx.sessions : liveSessions
    property int sessionIndex: 0
    readonly property var session: sessions[Math.min(sessionIndex, sessions.length - 1)] || null
    readonly property string sessionDirs: Quickshell.env("FOLIO_GREETER_SESSIONS")
        || ["/run/current-system/sw/share/wayland-sessions"].concat((Quickshell.env("XDG_DATA_DIRS") || "").split(":").filter(d => d).map(d => d + "/wayland-sessions")).join(":")
    Process {
        running: true
        environment: ({ "DIRS": root.sessionDirs })
        command: ["sh", "-c", `IFS=:; for d in $DIRS; do for f in "$d"/*.desktop; do [ -r "$f" ] || continue
            awk -v id="$(basename "$f" .desktop)" -F= '
                /^\\[/ { main = ($0 == "[Desktop Entry]") } !main { next }
                $1 == "Name" && name == "" { name = substr($0, 6) }
                $1 == "Exec" && exec == "" { exec = substr($0, 6) }
                $1 == "DesktopNames" { names = substr($0, 14) }
                ($1 == "Hidden" || $1 == "NoDisplay") && $2 == "true" { hide = 1 }
                END { if (!hide && name != "" && exec != "") print id "\\t" name "\\t" exec "\\t" names }' "$f"
            done; done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {}, list = [];
                for (const l of text.split("\n")) {
                    const f = l.split("\t");
                    if (f.length < 3 || seen[f[0]]) continue;
                    seen[f[0]] = true;
                    list.push({ "id": f[0], "name": f[1], "exec": f[2], "desktopNames": f[3] || "" });
                }
                // The default first, the rest by name.
                const want = Quickshell.env("FOLIO_GREETER_DEFAULT_SESSION") || "niri";
                list.sort((a, b) => (b.id === want) - (a.id === want) || a.name.localeCompare(b.name));
                root.liveSessions = list;
                root.sessionsRead = true;
                root.sessionIndex = Math.max(0, list.findIndex(s => s.id === want));
            }
        }
    }
    function chooseSession(i) {
        if (sessions.length < 2) return;
        sessionIndex = (i + sessions.length) % sessions.length;
    }
    // Exec= without field codes, split as a shell would split plain words.
    function argv(exec) {
        const out = [];
        const re = /"((?:[^"\\]|\\.)*)"|'([^']*)'|(\S+)/g;
        let m;
        while ((m = re.exec(exec)) !== null) {
            const word = m[1] !== undefined ? m[1].replace(/\\(.)/g, "$1") : m[2] !== undefined ? m[2] : m[3];
            if (/^%[fFuUdDnNickvm]$/.test(word)) continue;
            out.push(word);
        }
        return out;
    }
    function sessionEnv(s) {
        const env = ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=" + s.id, "DESKTOP_SESSION=" + s.id];
        const desktops = s.desktopNames.replace(/;/g, ":").replace(/^:+|:+$/g, "");
        if (desktops) env.push("XDG_CURRENT_DESKTOP=" + desktops);
        return env;
    }

    // ------------------------------------------------------------ the plate
    // The login plate: the desktop's own, or one of its collection at random
    // when Folio's selection asks for a random login.
    readonly property int randomArt: Math.floor(Math.random() * 720720)   // drawn once per run
    readonly property string plate: {
        if (fx && fx.plate) return fx.plate;
        const c = Art.collections.find(x => x.id === Theme.selection.collection);
        if (!c || !c.art.length || !Theme.selection.randomLogin) return Art.current;
        return c.art[randomArt % c.art.length].id;
    }

    property string liveHost: ""
    readonly property string host: fx ? fx.host : liveHost
    Process {
        running: true
        command: ["uname", "-n"]
        stdout: StdioCollector { onStreamFinished: root.liveHost = text.trim() }
    }

    // ------------------------------------------------------------ signing in
    property Login login: Login {
        onNotice: (message, error) => { root.message = message; root.messageError = error; }
        onFailed: message => root.refuse(/lock|too many|wait|denied|expired/i.test(message) ? message : "Not quite. The ink lifts; try again.")
        onBroke: message => { root.refuse(message); }
        onReady: root.accept()
        onLaunched: command => {
            root.phase = "launching";
            root.message = "Would start: " + command;
            root.messageError = false;
            harnessReset.restart();
        }
    }
    readonly property bool checking: login.checking

    function key(event) {
        const k = event.key;
        const shift = event.modifiers & Qt.ShiftModifier;
        if (phase !== "typing") return;
        // While the password is out, keys wait; Escape takes back one PAM hasn't asked for yet.
        if (checking) { if (k === Qt.Key_Escape && login.pending !== "") { login.pending = ""; type(""); } return; }
        if (k === Qt.Key_Tab || k === Qt.Key_Backtab) { moveFocus(k === Qt.Key_Backtab || shift ? -1 : 1); return; }
        if (focusPart === "power" && powerMenu) return;   // GreeterPower had it first
        if (k === Qt.Key_Escape) {
            if (focusPart !== "password") { focusPart = "password"; return; }
            if (buffer === "" && !login.listening && login.fingerSeen && !checking) { login.restart(); return; }
            type("");
            return;
        }
        if (focusPart === "user" || focusPart === "session") {
            const by = k === Qt.Key_Left || k === Qt.Key_Up ? -1 : k === Qt.Key_Right || k === Qt.Key_Down ? 1 : 0;
            if (by) { if (focusPart === "user") chooseUser(userIndex + by); else chooseSession(sessionIndex + by); return; }
            if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { focusPart = "password"; return; }
        }
        if (focusPart === "power" && (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || k === Qt.Key_Down || k === Qt.Key_Up)) { openPower(); return; }
        if (k === Qt.Key_Return || k === Qt.Key_Enter) { submit(); return; }
        if (k === Qt.Key_Backspace && (event.modifiers & Qt.ControlModifier)) { type(""); return; }
        if (k === Qt.Key_Backspace) { focusPart = "password"; type(buffer.slice(0, -1)); return; }
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return;
        const t = event.text;
        if (t && t.length > 0 && t.charCodeAt(0) >= 32 && t !== "\u007f") { focusPart = "password"; type((buffer + t).slice(0, 256)); }
    }
    readonly property var parts: ["password"].concat(users.length > 1 ? ["user"] : [], sessions.length > 1 ? ["session"] : [], ["power"])
    function moveFocus(by) {
        if (powerCountdown <= 0) powerMenu = false;
        const at = Math.max(0, parts.indexOf(focusPart));
        focusPart = parts[(at + by + parts.length) % parts.length];
    }
    function type(value) {
        liftTimer.stop();
        lifting = -1;
        buffer = value;
        if (messageError) { message = ""; messageError = false; }
    }
    function clearEntry() {
        liftTimer.stop();
        lifting = -1;
        buffer = "";
        message = "";
        messageError = false;
        peek = false;
    }
    function submit() {
        if (phase !== "typing" || buffer.length === 0 || checking) return;
        if (!login.available) { refuse("greetd isn't running, so nobody can sign in here."); return; }
        if (!session) { refuse("No sessions are installed. Ctrl+Alt+F2 opens a text console."); return; }
        message = "";
        messageError = false;
        const p = buffer;
        login.submit(p);
    }
    function accept() {
        if (phase !== "typing") return;
        phase = "opening";
        liftTimer.stop();
        lifting = -1;
        buffer = "";
        peek = false;
        closePower();
        focusPart = "password";
        message = "";
        launchTimer.restart();
    }
    function refuse(text) {
        if (phase !== "typing") { phase = "typing"; launchTimer.stop(); giveUp.stop(); marker.setText(""); }
        lifting = buffer.length;
        buffer = "";
        message = text;
        messageError = true;
        refused();
        liftTimer.interval = Math.max(1, 420 * Theme.motion);
        liftTimer.restart();
        // A fresh conversation, so the finger listens again.
        againTimer.restart();
    }
    Timer { id: againTimer; interval: 600; onTriggered: if (root.phase === "typing" && !root.login.active) root.login.begin(root.user.name) }
    Timer {
        id: liftTimer
        repeat: true
        onTriggered: {
            interval = Math.max(1, 28 * Theme.motion);
            root.lifting = Math.max(0, root.lifting - 1);
            if (root.lifting === 0) { root.lifting = -1; stop(); }
        }
    }
    // The page plays out, then greetd gets the session; greetd wants the
    // greeter gone soon after, so the animation comes first.
    Timer {
        id: launchTimer
        interval: Math.max(80, 1000 * Theme.motion)
        onTriggered: root.launch()
    }
    function launch() {
        const s = session;
        if (!s) { refuse("No session to start."); return; }
        marker.setText("launched " + s.id + "\n");
        login.launch(argv(s.exec), sessionEnv(s));
        giveUp.restart();
    }
    // greetd never answered the launch: say so and try again.
    Timer {
        id: giveUp
        interval: 8000
        onTriggered: if (root.phase === "opening" && !root.harness) { root.refuse("The session didn't start. Try again."); root.login.cancel(); }
    }
    FileView {
        id: marker
        path: (Quickshell.env("FOLIO_GREETER_STATE") || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/folio-greeter")) + "/launched"
        blockWrites: true
        printErrors: false
    }
    // Harness only: back to the start a moment after a pretend launch.
    Timer {
        id: harnessReset
        interval: 3000
        onTriggered: { root.phase = "typing"; root.message = ""; root.login.begin(root.user.name); root.resetPages(); }
    }
    signal resetPages()

    // ------------------------------------------------------------ power
    // Restart and Shut down count down on the menu (GreeterPower) and can be
    // cancelled. One countdown for every screen. The harness only says what
    // would run.
    property bool powerMenu: false
    property string powerAction: ""         // reboot | poweroff while counting down
    property int powerCountdown: -1
    property int powerCurrent: -1           // the keyboard's choice in the menu
    function openPower() { powerMenu = true; if (powerCurrent < 0) powerCurrent = powerCountdown > 0 ? 1 : 0; }
    function closePower() { powerMenu = false; powerCountdown = -1; powerAction = ""; powerCurrent = -1; powerTick.stop(); }
    function powerAct(act) {
        if (act === "cancel") { powerCountdown = -1; powerAction = ""; powerTick.stop(); powerCurrent = 0; return; }
        if (act !== "reboot" && act !== "poweroff") return;
        powerAction = act;
        powerCountdown = 5;
        powerCurrent = 1;                   // Cancel, under the keyboard
        powerTick.restart();
    }
    Timer {
        id: powerTick
        interval: 1000; repeat: true
        onTriggered: {
            if (--root.powerCountdown > 0) return;
            const act = root.powerAction;
            root.closePower();
            root.runPower(act);
        }
    }
    function runPower(action) {
        if (harness) { message = (action === "reboot" ? "Restart" : "Shut down") + " would start now."; messageError = false; return; }
        powerProc.command = ["systemctl", action === "reboot" ? "reboot" : "poweroff"];
        powerProc.running = true;
    }
    Process {
        id: powerProc
        stderr: StdioCollector { id: powerErr }
        onExited: code => { if (code !== 0) { root.message = "Couldn't " + (command[1] === "reboot" ? "restart" : "shut down") + ": " + (powerErr.text.trim() || "refused"); root.messageError = true; } }
    }

    // ------------------------------------------------------------ windows
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "folio:greeter"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: Theme.paper
            GreeterPage {
                anchors.fill: parent
                greeter: root
            }
        }
    }

    // ------------------------------------------------------------ fixtures
    readonly property var sessionsTwo: [
        { "id": "niri", "name": "Niri", "exec": "niri-session", "desktopNames": "niri" },
        { "id": "gnome", "name": "GNOME", "exec": "/nix/store/…-gnome-session-with-desktop-env", "desktopNames": "GNOME" }
    ]
    readonly property var fixtures: ({
        "normal": { "users": [{ "name": "mariano", "real": "Mariano", "avatar": "" }], "sessions": sessionsTwo, "host": "bonhart", "battery": 84, "layout": "US" },
        "fingerprint": { "users": [{ "name": "mariano", "real": "Mariano", "avatar": "" }], "sessions": sessionsTwo, "host": "bonhart", "battery": 84, "layout": "US", "finger": true },
        "wrong": { "users": [{ "name": "mariano", "real": "Mariano", "avatar": "" }], "sessions": sessionsTwo, "host": "bonhart", "battery": 84, "layout": "US", "typed": "hunter2", "submit": true },
        "lockout": { "users": [{ "name": "mariano", "real": "Mariano", "avatar": "" }], "sessions": sessionsTwo, "host": "bonhart", "battery": 12, "layout": "ES", "typed": "hunter2", "submit": true, "lockout": "The account is locked due to 3 failed logins. (2 minutes left to unlock.)" },
        "users": { "users": [{ "name": "mariano", "real": "Mariano", "avatar": "" }, { "name": "invitado", "real": "Invitado", "avatar": "" }, { "name": "ana", "real": "Ana Pérez", "avatar": "" }], "sessions": sessionsTwo, "host": "bonhart", "battery": 84, "layout": "US" },
        "stress": {
            "users": [{ "name": "mariano", "real": "Mariano Miguel de los Santos Echeverría Uriarte Fernández de la Torre y Montenegro", "avatar": "" }, { "name": "x", "real": "", "avatar": "" }],
            "sessions": [{ "id": "niri", "name": "Niri", "exec": "niri-session", "desktopNames": "niri" }, { "id": "long", "name": "A session with a very long name that a desktop file might really carry (Wayland, experimental)", "exec": "true", "desktopNames": "" }, { "id": "gnome", "name": "GNOME", "exec": "gnome-session", "desktopNames": "GNOME" }],
            "host": "bonhart-workstation-with-a-hostname-much-longer-than-anyone-would-type", "battery": 100, "layout": "ES", "finger": true, "typed": "correct horse battery staple"
        },
        "empty": { "users": [{ "name": "mariano", "real": "", "avatar": "" }], "sessions": [], "host": "", "battery": -1, "layout": "" }
    })

    IpcHandler {
        target: "greeter"
        // normal | fingerprint | wrong | lockout | users | stress | empty; anything else is live.
        function fixture(name: string): void {
            const f = root.fixtures[name] || null;
            root.fx = f;
            root.phase = "typing";
            root.focusPart = "password";
            root.closePower();
            root.userIndex = 0;
            root.sessionIndex = 0;
            root.clearEntry();
            root.login.fx = f || {};
            root.login.fingerSeen = false;
            root.login.begin(root.user.name);
            root.resetPages();
            if (!f) return;
            if (f.typed) root.buffer = f.typed;
            if (f.submit) root.submit();
        }
        // Harness only: a finger on the reader while PAM listens.
        function touch(): void { root.login.touch(); }
        function focus(part: string): void { if (root.parts.indexOf(part) >= 0) root.focusPart = part; }
        function power(): void { root.focusPart = "power"; root.openPower(); }
        function peek(on: bool): void { root.peek = on; }
        function state(): string {
            return JSON.stringify({ "phase": root.phase, "focus": root.focusPart, "user": root.user.name, "session": root.session ? root.session.id : "",
                "listening": root.login.listening, "awaiting": root.login.awaiting, "checking": root.checking, "message": root.message,
                "sessions": root.sessions.map(s => s.id), "users": root.users.map(u => u.name), "plate": root.plate });
        }
    }
}
