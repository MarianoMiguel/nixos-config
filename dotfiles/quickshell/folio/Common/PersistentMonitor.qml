import QtQuick
import Quickshell
import Quickshell.Io

// A command that should run as long as the shell does: an event stream
// (gdbus monitor, nmcli monitor, udevadm monitor, inotifywait) whose silence
// would otherwise read as "nothing happened". When it ends it starts again
// after a pause that doubles with each run that ended quickly (minDelay,
// twice that, four times… up to maxDelay) and starts over at minDelay once
// a run has lasted `healthy`.
//
// The pause runs in the child (sleep, then exec the command), not on a QML
// Timer: timers can stall while no window draws (every display off), which
// is when a lock watcher matters most.
//
// `restarted()` fires when a later run is about to start, so the owner can
// read again whatever it may have missed. Use it like a Process:
//
//     PersistentMonitor {
//         name: "Network: nmcli monitor"
//         running: true
//         command: ["nmcli", "monitor"]
//         stdout: SplitParser { onRead: line => root.changed() }
//         onRestarted: root.refresh()
//     }
Scope {
    id: root

    property string name: command.length > 0 ? String(command[0]) : "monitor"
    property bool running: false
    property var command: []
    property alias stdout: proc.stdout
    property int minDelay: 1000
    property int maxDelay: 30000
    property int healthy: 30000

    readonly property bool alive: proc.running
    property int restarts: 0                // runs started after the first
    property string lastError: ""           // the command's last line on stderr
    signal restarted()

    QtObject {
        id: st
        property int delay: 0               // ms the next run waits
        property int failures: 0            // runs in a row that ended quickly
        property real since: 0              // when the current run started
        property int code: 0
    }

    onRunningChanged: sync()
    Component.onCompleted: sync()
    function sync() {
        if (!running) { st.failures = 0; proc.running = false; return; }
        if (!proc.running) start(0);
    }
    function start(delay) {
        st.delay = delay;
        st.since = Date.now() + delay;
        lastError = "";
        proc.running = true;
    }
    function ended() {
        if (!running || proc.running) return;
        if (Date.now() - st.since >= healthy) st.failures = 0;
        const delay = Math.min(maxDelay, minDelay * Math.pow(2, st.failures));
        st.failures++;
        if (st.failures <= 5 || st.failures % 20 === 0)
            console.warn(name + " ended (" + st.code + (lastError ? ": " + lastError : "") + "); starting again in " + delay / 1000 + " s");
        restarts++;                         // before start: a command may depend on it
        start(delay);
    }

    Process {
        id: proc
        command: ["sh", "-c", "sleep \"$1\" || exit; shift; printf '\\036started\\n' >&2; exec \"$@\"", "sh", String(st.delay / 1000)].concat(root.command)
        stderr: SplitParser {
            onRead: line => {
                if (line === "\u001estarted") { if (root.restarts > 0) root.restarted(); return; }
                if (line.trim()) root.lastError = line.trim().slice(0, 200);
            }
        }
        onExited: code => st.code = code
        // Also when it could not start at all. Later, so Process has settled.
        onRunningChanged: if (!running) Qt.callLater(root.ended)
    }
}
