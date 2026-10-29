pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Changing mode, ink or plate. azure-folio re-themes the apps (GTK, Qt,
// Chrome, the terminal) and takes a few seconds; Folio shows the choice at
// once through Theme.pending and says it is still applying. Choices made
// while it runs are merged into one more run. If it fails, the choice is
// taken back and a toast says so. In the harness nothing runs.
// (Not named Palette: Qt Quick has a Palette type, which wins the name.)
Singleton {
    id: root

    property bool busy: false
    property string label: ""            // "dark mode", "Cobalt", "Ronin"
    property var queued: null            // a patch waiting for the run in progress
    property var running: ({})

    // patch: { mode, ink, collection, art }
    function set(patch, label) {
        Theme.pending = Object.assign({}, Theme.pending, patch);
        root.label = label || "";
        if (busy) { queued = Object.assign({}, queued || {}, patch); return; }
        run(patch);
    }
    function args(patch) {
        const a = ["azure-folio", "set"];
        for (const k of ["mode", "ink", "collection", "art"]) if (k in patch) a.push("--" + k, String(patch[k]));
        return a;
    }
    function run(patch) {
        busy = true;
        running = patch;
        giveUp.restart();
        if (Sys.harness) { Sys.run(args(patch)); fake.restart(); return; }
        proc.command = args(patch);
        proc.running = true;
    }
    function finished(ok, detail) {
        giveUp.stop();
        if (!ok) {
            const p = Object.assign({}, Theme.pending);
            for (const k in running) delete p[k];
            Theme.pending = p;
            Toasts.show("Could not change the look" + (detail ? ": " + detail : ""), { "icon": "palette", "timeout": 6000 });
        }
        if (queued) { const q = queued; queued = null; run(q); return; }
        busy = false;
    }

    Process {
        id: proc
        stderr: StdioCollector { id: err }
        onExited: code => root.finished(code === 0, err.text.trim().split("\n").slice(-1)[0] || "")
    }
    Timer { id: fake; interval: 1200; onTriggered: root.finished(true, "") }
    // A run that never ends must not leave the choice half-applied forever.
    Timer {
        id: giveUp; interval: 45000
        onTriggered: { if (proc.running) proc.running = false; Theme.pending = {}; root.queued = null; root.busy = false; }
    }
}
