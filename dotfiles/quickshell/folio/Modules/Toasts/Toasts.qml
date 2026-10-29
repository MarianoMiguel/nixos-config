import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services

// Toasts (Services/Toasts) bottom-centre, just above the dock's band, on the
// focused screen. Newest on top and at most three; a toast never moves while
// a newer one arrives, so its button stays under the pointer. Each rises from
// under the dock (or from behind the toast below) and prints in, and leaves
// the way it came.
Scope {
    id: root

    readonly property real cardHeight: 48
    readonly property real gap: 8
    readonly property int most: 3

    // Fixtures post toasts with no effect; empty clears them without running
    // their actions.
    function noop() {}
    IpcHandler {
        target: "toasts"
        function fixture(name: string): void {
            for (const t of Toasts.items.slice()) Toasts.take(t.id);
            const undo = (text, icon) => Toasts.show(text, { "action": "Undo", "onAction": root.noop, "onTimeout": root.noop, "timeout": 20000, "icon": icon || "" });
            if (name === "normal") {
                undo("Screenshot deleted", "image");
                Toasts.show("Shutting down", { "action": "Cancel", "onAction": root.noop, "onTimeout": root.noop, "timeout": 20000, "countdown": true, "icon": "power" });
            } else if (name === "stress") {
                undo("3 notifications cleared", "bell");
                Toasts.show("Copied to clipboard", { "timeout": 20000 });
                undo("“Quarterly planning with product, design, engineering and the extended leadership team.png” moved to Trash", "image");
                Toasts.show("Restarting", { "action": "Cancel", "onAction": root.noop, "onTimeout": root.noop, "timeout": 120000, "countdown": true, "icon": "reload" });
                undo("Look “before-the-sidebar-v2-with-a-much-longer-name-than-anyone-would-type” deleted", "");
            }
        }
        // The newest toast's action (Undo, Cancel), or its close.
        function act(): void { const t = Toasts.items.slice().reverse().find(x => x.action); if (t) Toasts.act(t.id); }
        function dismiss(): void { const t = Toasts.items[Toasts.items.length - 1]; if (t && !t.countdown) Toasts.dismiss(t.id); }
    }

    // The cards on screen: the newest three, plus any still leaving.
    ListModel { id: cards }
    property var snaps: ({})
    Connections { target: Toasts; function onItemsChanged() { root.sync(); } }
    function sync() {
        const shown = Toasts.items.slice(-most);
        const ids = shown.map(t => t.id);
        const s = Object.assign({}, snaps);
        for (const t of shown) s[t.id] = t;
        snaps = s;
        for (let i = 0; i < cards.count; i++) {
            const c = cards.get(i);
            const want = ids.indexOf(c.tid) >= 0;
            if (c.leaving === want) cards.setProperty(i, "leaving", !want);
        }
        for (const t of shown) {
            let at = cards.count, found = false;
            for (let i = 0; i < cards.count; i++) {
                if (cards.get(i).tid === t.id) { found = true; break; }
                if (cards.get(i).tid > t.id) { at = Math.min(at, i); }
            }
            if (!found) cards.insert(at, { "tid": t.id, "leaving": false, "rank": 0 });
        }
        rerank();
    }
    // A card's rank counts the older cards still staying; leaving cards keep
    // theirs, so they sink to the slot below the one they had.
    function rerank() {
        let n = 0;
        for (let i = 0; i < cards.count; i++) {
            if (cards.get(i).leaving) continue;
            if (cards.get(i).rank !== n) cards.setProperty(i, "rank", n);
            n++;
        }
    }
    function drop(tid) {
        for (let i = 0; i < cards.count; i++)
            if (cards.get(i).tid === tid && cards.get(i).leaving) { cards.remove(i); rerank(); break; }
        const s = Object.assign({}, snaps);
        if (!Toasts.items.find(t => t.id === tid)) delete s[tid];
        snaps = s;
    }

    PanelWindow {
        id: win
        screen: Shell.screenFor(Quickshell.screens)
        visible: cards.count > 0
        color: "transparent"
        anchors.bottom: true
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: 600
        implicitHeight: 90 + root.most * (root.cardHeight + root.gap) + 40
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "folio:toasts"
        // Input on the staying cards, frost behind the printed ones (at most
        // three of each, so three fixed regions).
        mask: Region {
            Region { item: win.hit[0] || null }
            Region { item: win.hit[1] || null }
            Region { item: win.hit[2] || null }
        }
        BackgroundEffect.blurRegion: Region {
            Region { item: win.frost[0] || null; radius: Theme.rL }
            Region { item: win.frost[1] || null; radius: Theme.rL }
            Region { item: win.frost[2] || null; radius: Theme.rL }
        }
        property var hit: []
        property var frost: []
        function collect() {
            const a = [], b = [];
            for (let i = 0; i < stack.count; i++) {
                const c = stack.itemAt(i);
                if (c && !c.leaving) a.push(c.surface);
                if (c && c.printed) b.push(c.surface);
            }
            hit = a.slice(-root.most);
            frost = b.slice(-root.most);
        }

        // The band the toasts rest on and the dock's top edge they rise from.
        readonly property real restBottom: height - 90
        readonly property real dockTop: height - 78

        Item {
            id: clip
            width: parent.width
            height: win.dockTop
            clip: true

            Repeater {
                id: stack
                model: cards
                onItemAdded: win.collect()
                onItemRemoved: win.collect()
                ToastCard {
                    id: card
                    required property var model
                    readonly property int tid: model.tid
                    readonly property int rank: model.rank
                    readonly property real slot: win.restBottom - (rank + 1) * root.cardHeight - rank * root.gap
                    toast: root.snaps[tid] || ({})
                    leaving: model.leaving
                    x: Math.round((win.width - width) / 2)
                    targetY: slot - pad
                    startY: (rank === 0 ? win.dockTop + 4 : slot + root.cardHeight + root.gap) - pad
                    z: leaving || !ready ? 0 : 1
                    onGone: root.drop(tid)
                    onLeavingChanged: win.collect()
                    onPrintedChanged: win.collect()
                }
            }
        }
    }
}
