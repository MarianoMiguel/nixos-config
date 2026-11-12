pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Focus sessions: a countdown that silences notifications. A running session
// survives a shell restart (its end time is saved). Do not disturb (dnd) is
// the same silence without an end: on until turned off, also saved. The
// harness keeps its state in its own runtime directory.
Singleton {
    id: root

    property real endsAt: 0
    property int duration: 25 * 60
    property bool dnd: false
    property real now: Date.now()
    readonly property bool active: endsAt > now
    readonly property int remaining: active ? Math.round((endsAt - now) / 1000) : 0
    readonly property real progress: active ? 1 - remaining / Math.max(1, duration) : 0
    readonly property string clock: Math.floor((active ? remaining : duration) / 60) + ":" + String((active ? remaining : duration) % 60).padStart(2, "0")
    signal finished()

    function start(minutes) {
        duration = Math.round((minutes || 25) * 60);
        now = Date.now();
        endsAt = now + duration * 1000;
        save();
    }
    function stop() { endsAt = 0; save(); }
    function toggle() { if (active) stop(); else start(duration / 60); }
    function setDnd(on) { dnd = !!on; save(); }

    Timer {
        interval: 1000; repeat: true
        running: root.endsAt > 0
        onTriggered: {
            root.now = Date.now();
            if (root.endsAt > 0 && root.endsAt <= root.now) { root.endsAt = 0; root.save(); root.finished(); }
        }
    }

    FileView {
        id: file
        path: Sys.harness ? Quickshell.env("XDG_RUNTIME_DIR") + "/folio-focus.json" : Quickshell.statePath("focus.json")
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.duration = s.duration || root.duration;
                root.now = Date.now();
                root.endsAt = s.endsAt > root.now ? s.endsAt : 0;
                root.dnd = s.dnd === true;
            } catch (e) {}
        }
    }
    function save() { file.setText(JSON.stringify({ "endsAt": endsAt, "duration": duration, "dnd": dnd })); }
}
