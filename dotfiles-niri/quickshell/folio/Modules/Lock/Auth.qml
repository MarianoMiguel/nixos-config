import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import qs.Services

// The lock's authentication. Passwords go through a password-only PAM
// service: folio-lock, else DMS's dankshell (both password-only on purpose),
// else login. Fingerprints run in a parallel context of their own
// (Services/Fingerprint) only when a reader has prints enrolled and the
// system's login stack uses pam_fprintd. The harness never touches PAM: it
// accepts "folio" and refuses anything else.
Scope {
    id: root

    property bool active: false             // the lock is up
    readonly property bool harness: (Quickshell.env("FOLIO_HARNESS") || "") !== ""
    readonly property bool checking: passwd.active || fakeCheck.running
    readonly property bool fingerprint: !harness && Fingerprint.lockReady && fprint.tries < 5 || harness && Fingerprint.forced === true
    property string service: "login"

    signal accepted()
    signal refused(string message)
    signal notice(string message)           // fingerprint misses, PAM notes

    property string pending: ""
    property var notes: []

    function check(password) {
        if (checking) return;
        pending = password;
        notes = [];
        if (harness) { fakeCheck.restart(); return; }
        if (!passwd.start()) { pending = ""; refused("Couldn't start the password check."); return; }
        stall.restart();
    }
    function stop() {
        pending = "";
        fakeCheck.stop();
        stall.stop();
        retry.stop();
        if (passwd.active) passwd.abort();
        if (fprint.active) fprint.abort();
    }
    onActiveChanged: {
        if (active) { Fingerprint.probe(); fprint.tries = 0; fprint.errors = 0; startFprint.restart(); }
        else stop();
    }

    // Resolve the password service once, from what the system provides.
    Process {
        running: !root.harness
        command: ["sh", "-c", "for s in folio-lock dankshell; do [ -e /etc/pam.d/$s ] && { echo $s; exit; }; done; echo login"]
        stdout: StdioCollector { onStreamFinished: root.service = text.trim() || "login" }
    }

    Timer {
        id: fakeCheck
        interval: 380
        onTriggered: {
            const ok = root.pending === "folio";
            root.pending = "";
            if (ok) root.accepted(); else root.refused("Not quite. The ink lifts; try again.");
        }
    }

    PamContext {
        id: passwd
        config: root.service
        configDirectory: "/etc/pam.d"
        onPamMessage: if (message && !responseRequired) root.notes = root.notes.concat([message])
        onResponseRequiredChanged: {
            if (!responseRequired) return;
            respond(root.pending);
            root.pending = "";
        }
        onCompleted: result => {
            stall.stop();
            root.pending = "";
            const note = root.notes.join(" ");
            if (result === PamResult.Success) root.accepted();
            else if (result === PamResult.MaxTries) root.refused(note || "Too many tries. Wait a moment, then try again.");
            else if (result === PamResult.Error) root.refused(note || "Couldn't check the password. Try again.");
            else root.refused(note || "Not quite. The ink lifts; try again.");
        }
        onError: error => {
            stall.stop();
            root.pending = "";
            root.refused("Couldn't check the password (" + PamError.toString(error) + ").");
        }
    }
    // A check that never answers must not leave the lock unusable.
    Timer {
        id: stall
        interval: 15000
        onTriggered: if (passwd.active) { passwd.abort(); root.pending = ""; root.refused("The check took too long. Try again."); }
    }

    // Fingerprints: always listening while locked; misses retry.
    Timer { id: startFprint; interval: 400; onTriggered: fprint.listen() }
    Connections {
        target: Fingerprint
        function onLockReadyChanged() { fprint.listen(); }
    }
    Timer { id: retry; interval: Math.min(1500 * Math.pow(2, fprint.errors), 30000); onTriggered: fprint.listen() }
    PamContext {
        id: fprint
        property int tries: 0
        property int errors: 0
        config: Fingerprint.config || "login"
        configDirectory: Fingerprint.configDirectory || "/etc/pam.d"
        function listen() {
            if (root.harness || !root.active || active || !Fingerprint.lockReady || !Fingerprint.config || tries >= 5) return;
            if (!start()) { errors++; if (errors < 8) retry.restart(); }
        }
        onCompleted: result => {
            if (!root.active) return;
            if (result === PamResult.Success) { root.accepted(); return; }
            if (result === PamResult.Error) {
                errors++;
                if (errors < 8) retry.restart();
                return;
            }
            tries++;
            root.notice(tries < 5 ? "Not that finger. Try again, or type your password." : "Fingerprint is off until you type your password.");
            listen();
        }
        onError: _ => { errors++; if (errors < 8) retry.restart(); }
    }
}
