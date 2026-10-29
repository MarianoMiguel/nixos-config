pragma Singleton
import QtQuick
import Quickshell

// Toasts: short messages above the dock. Destructive actions use undo()
// instead of asking "are you sure?": the change shows at once, commits when
// the toast times out, and Undo puts it back. countdown() does the same for
// actions that cannot be undone once done (power off): Cancel stops them.
Singleton {
    id: root

    property var items: []
    property int seq: 0
    property real now: Date.now()

    function show(text, opts) {
        opts = opts || {};
        const t = {
            "id": ++seq, "text": text, "icon": opts.icon || "", "action": opts.action || "",
            "onAction": opts.onAction || null, "onTimeout": opts.onTimeout || null,
            "timeout": opts.timeout || 4000, "started": Date.now(), "countdown": !!opts.countdown
        };
        items = items.concat([t]);
        return t.id;
    }
    function undo(text, commit, restore, icon) {
        Sounds.play("trash");                   // something set aside, still within reach
        return show(text, { "action": "Undo", "onAction": restore, "onTimeout": commit, "timeout": 6000, "icon": icon || "" });
    }
    function countdown(text, run, seconds, icon) {
        return show(text, { "action": "Cancel", "onTimeout": run, "timeout": (seconds || 5) * 1000, "countdown": true, "icon": icon || "power" });
    }
    function take(id) {
        const t = items.find(x => x.id === id);
        items = items.filter(x => x.id !== id);
        return t;
    }
    function act(id) { const t = take(id); if (t && t.onAction) t.onAction(); }
    function dismiss(id) { const t = take(id); if (t && t.onTimeout) t.onTimeout(); }
    function remaining(t) { return Math.max(0, Math.ceil((t.started + t.timeout - now) / 1000)); }
    // Pause a toast while it is hovered: its clock stops and resumes after.
    function hold(id, on) {
        items = items.map(t => {
            if (t.id !== id) return t;
            if (on && !t.heldAt) return Object.assign({}, t, { "heldAt": Date.now() });
            if (!on && t.heldAt) return Object.assign({}, t, { "started": t.started + (Date.now() - t.heldAt), "heldAt": 0 });
            return t;
        });
    }

    Timer {
        interval: 200; repeat: true
        running: root.items.length > 0
        onTriggered: {
            root.now = Date.now();
            for (const t of root.items.slice())
                if (!t.heldAt && root.now >= t.started + t.timeout) root.dismiss(t.id);
        }
    }
}
