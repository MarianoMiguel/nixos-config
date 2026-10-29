pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Clipboard history: text copied while the shell runs (wl-paste --watch),
// newest first, deduplicated, the last 50, kept across restarts. Entries a
// password manager marks as secret are never recorded.
Singleton {
    id: root

    property var items: []           // [{text, time}]
    readonly property int limit: 50
    readonly property int maxLength: 20000

    function add(text) {
        if (!text || !text.trim()) return;
        text = text.slice(0, maxLength);
        items = [{ "text": text, "time": Date.now() }].concat(items.filter(x => x.text !== text)).slice(0, limit);
        save();
    }
    function remove(text) { items = items.filter(x => x.text !== text); save(); }
    // Puts a removed entry back where it was (undo).
    function restore(entry, index) {
        const list = items.filter(x => x.text !== entry.text);
        list.splice(Math.max(0, Math.min(index, list.length)), 0, entry);
        items = list.slice(0, limit);
        save();
    }
    function copy(text) { Quickshell.execDetached(["wl-copy", "--", text]); }
    // Saved only once the old history has loaded, so a copy made at start-up
    // never overwrites it.
    property bool ready: false
    function save() { if (ready) file.setText(JSON.stringify(items)); }

    // Each new selection runs the script: text arrives on stdin, ends in RS.
    Process {
        id: watcher
        running: true
        command: ["wl-paste", "--type", "text", "--watch", "sh", "-c",
            "[ \"$CLIPBOARD_STATE\" = data ] || exit 0; " +
            "if wl-paste --list-types 2>/dev/null | grep -qx x-kde-passwordManagerHint; then cat >/dev/null; exit 0; fi; " +
            "head -c 262144; printf '\\036'"]
        stdout: SplitParser {
            splitMarker: "\u001e"
            onRead: data => root.add(data)
        }
        onExited: retry.start()
    }
    // wl-paste ends when the compositor goes away; try again, slowly.
    Timer { id: retry; interval: 5000; onTriggered: watcher.running = true }

    FileView {
        id: file
        // The test harness keeps its own history.
        path: Quickshell.statePath(Quickshell.env("FOLIO_HARNESS") ? "clipboard-harness.json" : "clipboard.json")
        printErrors: false
        onLoaded: {
            try {
                const saved = JSON.parse(text());
                // Entries copied before the file loaded stay on top.
                const seen = new Set(root.items.map(x => x.text));
                root.items = root.items.concat(saved.filter(x => x && x.text && !seen.has(x.text))).slice(0, root.limit);
            } catch (e) {}
            root.ready = true;
            if (root.items.length) root.save();
        }
        onLoadFailed: { root.ready = true; if (root.items.length) root.save(); }
    }
}
