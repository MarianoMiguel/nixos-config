pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Lock state for the whole shell. The Lock module draws the lock screen when
// locked is true. logind's PrepareForSleep locks, so resuming never shows the
// desktop first; logind's Lock and Unlock (loginctl lock-session,
// unlock-session) lock and unlock, but only for this shell's own graphical
// session: an SSH or Tailscale login is a session of its own, and its
// `loginctl unlock-session` must not open the screen. LockedHint follows the
// lock (loginctl shows it; idle and power tools read it).
//
// The shell runs as a systemd user service, outside any session (so does
// niri), so the session is the first graphical session of this user among:
// the one the shell's own process is in (when started inside the session),
// XDG_SESSION_ID (niri-session imports it into the user manager), and the
// user's Display (logind's pick of the user's graphical session). The
// watcher looks it up before it listens, so every restart looks again.
// Until a session is found a Lock from any session still locks (fail
// closed) and no Unlock opens.
//
// In the harness the watcher is off (FOLIO_HARNESS_LOGIND=1 turns it on, to
// hear the real logind read-only) and LockedHint goes through Sys.run, so it
// is recorded, not sent.
//
// IPC `session`: status (the session found, the lock, the watcher); in the
// harness only, feed LINE hands the parser a line as the watcher prints it.
Singleton {
    id: root

    property bool locked: false
    signal unlocked()

    property string sessionId: ""
    property string sessionPath: ""         // /org/freedesktop/login1/session/…

    function lock() { locked = true; }
    function unlock() { locked = false; unlocked(); }

    // Lock first, then sleep once the lock screen is up.
    function lockThen(command) {
        lock();
        pending = command;
        sleepAfterLock.restart();
    }
    property var pending: null
    Timer {
        id: sleepAfterLock
        interval: 700
        onTriggered: {
            if (!root.pending) return;
            Sys.run(root.pending);
            root.pending = null;
        }
    }

    onLockedChanged: hint()
    function hint() {
        if (sessionPath)
            Sys.run(["busctl", "--system", "call", "org.freedesktop.login1", sessionPath,
                     "org.freedesktop.login1.Session", "SetLockedHint", "b", locked ? "true" : "false"]);
    }

    // gdbus monitor prints a signal as "<path>: <interface>.<member> <args>".
    readonly property string sleepLine: "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (true,)"
    // What a line asks for: sleep, lock, unlock, foreign (another session's
    // lock or unlock), or "" (anything else).
    function classify(line, path) {
        if (line === sleepLine) return "sleep";
        const m = /^(\/[A-Za-z0-9_\/]*): org\.freedesktop\.login1\.Session\.(Lock|Unlock) \(\)$/.exec(line);
        if (!m) return "";
        const kind = m[2] === "Lock" ? "lock" : "unlock";
        if (path !== "" && m[1] === path) return kind;
        if (path === "" && kind === "lock") return "lock";
        return "foreign";
    }
    function handle(line) {
        if (line.startsWith("session ")) {
            const f = line.split(" ");
            if (f.length === 3 && f[2].startsWith("/org/freedesktop/login1/session/") && f[2] !== sessionPath) {
                sessionId = f[1];
                sessionPath = f[2];
                hint();
            } else if (sessionPath === "" && f[2] === "-") console.warn("Session: no graphical session found; loginctl unlock-session is ignored");
            return "session";
        }
        const what = classify(line, sessionPath);
        if (what === "sleep" || what === "lock") lock();
        else if (what === "unlock") unlock();
        else if (what === "foreign") console.warn("Session: ignored, not this session:", line);
        return what;
    }

    PersistentMonitor {
        id: watcher
        name: "Session: logind watcher"
        running: !Sys.harness || Quickshell.env("FOLIO_HARNESS_LOGIND") === "1"
        maxDelay: 5000
        command: ["sh", "-c", `
            uid=$(id -u)
            obj() { sed -n 's/^o "\\(.*\\)"$/\\1/p'; }
            mgr() { busctl --system call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager "$@" 2>/dev/null; }
            prop() { busctl --system get-property org.freedesktop.login1 "$1" org.freedesktop.login1.Session "$2" 2>/dev/null; }
            # A graphical session of this user.
            ours() {
                [ -n "$1" ] || return 1
                case $(prop "$1" Type) in 's "wayland"'|'s "x11"'|'s "mir"') ;; *) return 1 ;; esac
                [ "$(prop "$1" User | cut -d' ' -f2)" = "$uid" ]
            }
            found() { id=$(prop "$1" Id | sed -n 's/^s "\\(.*\\)"$/\\1/p'); echo "session \${id:--} $1"; }
            p=$(mgr GetSessionByPID u $$ | obj)
            ours "$p" || { [ -n "$XDG_SESSION_ID" ] && p=$(mgr GetSession s "$XDG_SESSION_ID" | obj); }
            if ! ours "$p"; then
                u=$(mgr GetUser u "$uid" | obj)
                p=$([ -n "$u" ] && busctl --system get-property org.freedesktop.login1 "$u" org.freedesktop.login1.User Display 2>/dev/null | sed -n 's/^(so) "[^"]*" "\\(.*\\)"$/\\1/p')
            fi
            if ours "$p"; then found "$p"; else echo "session - -"; fi
            exec gdbus monitor --system --dest org.freedesktop.login1`]
        stdout: SplitParser { onRead: line => root.handle(line) }
    }

    IpcHandler {
        target: "session"
        function status(): string {
            return JSON.stringify({ "session": root.sessionId, "path": root.sessionPath, "locked": root.locked,
                                    "watcher": { "running": watcher.running, "alive": watcher.alive, "restarts": watcher.restarts } });
        }
        function feed(line: string): string {
            if (!Sys.harness) { console.warn("Session: feed works only in the harness"); return "refused"; }
            return root.handle(line) || "none";
        }
    }
}
