import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets

// The desktop's menu: a right click on bare wallpaper. The wallpaper's
// clicks reach dotfiles/quickshell/desktop-click (its own Quickshell
// instance on the Bottom layer, under every window), which asks for this
// menu over IPC: `qs ipc -c folio call desktop menu <screen> <x> <y>`, in
// that screen's coordinates. It opens there, under and right of the point,
// kept on screen (Widgets/ContextMenu): the wallpaper, the theme's quick
// action (Folio prints the collection's next plate, Lumen turns to the next
// sky), Appearance, Displays, a terminal and Settings.
//
// IPC `desktop`: menu SCREEN X Y ("" for the focused screen, a negative X
// or Y for its middle), close, choose INDEX (as a click would), state, and
// fixture normal | stress | empty ("" for the live menu). In the harness
// what the items change is only recorded (Sys.run, `settings dryrun`).
Scope {
    id: root

    property string fixture: ""
    property string lastChosen: ""
    property var openOn: null                // the ContextMenu that is open

    readonly property var skies: [{ "id": "orbit", "name": "Orbit" }, { "id": "prism", "name": "Prism" }, { "id": "glow", "name": "Glow" }, { "id": "haze", "name": "Haze" }]

    // The theme's quick action: Folio's next plate (as the launcher's "Next
    // plate"), Lumen's next sky; none when the collection has one plate.
    function quick() {
        if (Theme.prints) {
            const col = Art.collections.find(c => c.id === Theme.selection.collection);
            if (!col || col.art.length < 2) return null;
            const n = ((Theme.selection.art || 0) + 1) % col.art.length;
            const title = col.art[n].title || "";
            return { "label": "Next plate", "icon": "reload", "detail": title,
                     "run": () => Theming.set({ "art": n }, "“" + title + "”") };
        }
        const at = Math.max(0, skies.findIndex(s => s.id === (Theme.selection.sky || "orbit")));
        const next = skies[(at + 1) % skies.length];
        return { "label": "Next sky", "icon": "sparkle", "detail": next.name, "run": () => Theming.set({ "sky": next.id }, next.name) };
    }
    // Ghostty in a scope of its own (Apps); any terminal when it is missing.
    function terminal() {
        const e = DesktopEntries.byId("com.mitchellh.ghostty") || DesktopEntries.heuristicLookup("ghostty");
        if (e) Apps.launch(e);
        else Sys.run(Apps.scoped("xdg-terminal-exec", ["xdg-terminal-exec"]));
    }
    function live() {
        const list = [{ "label": "Change wallpaper…", "icon": "image", "detail": "Super Y", "run": () => Shell.openSettings("wallpaper") }];
        const q = quick();
        if (q) list.push(q);
        return list.concat([
            { "rule": true },
            { "label": "Appearance…", "icon": "palette", "run": () => Shell.openSettings("appearance") },
            { "label": "Display settings…", "icon": "display", "run": () => Shell.openSettings("displays") },
            { "rule": true },
            { "label": "Open Terminal", "icon": "terminal", "detail": "Super T", "run": () => root.terminal() },
            { "rule": true },
            { "label": "Settings…", "icon": "gear", "detail": "Super ,", "run": () => Shell.openSettings("") }
        ]);
    }
    // Fixture rows only record what they would do.
    function dry(label) { return () => Sys.run(["true", "desktop menu: " + label]); }
    function stress() {
        const long = "Print “The Great Wave off Kanagawa, from Thirty-six Views of Mount Fuji, c. 1831” in Cobalt";
        const list = [
            { "label": long, "icon": "image", "detail": "The Great Wave off Kanagawa, from Thirty-six Views of Mount Fuji", "run": dry("long") },
            { "label": "Next plate", "icon": "reload", "detail": "Under the Wave off Kanagawa (Kanagawa oki nami ura), also known as The Great Wave", "run": dry("next") },
            { "rule": true },
            { "label": "Disabled: no other plate in this collection of exactly one plate", "icon": "image", "disabled": true, "run": dry("disabled") },
            { "label": "Appearance…", "icon": "palette", "run": dry("appearance") },
            { "label": "Display settings…", "icon": "display", "detail": "3 displays", "run": dry("displays") },
            { "rule": true },
            { "rule": true },
            { "label": "Open Terminal", "icon": "terminal", "detail": "Super T", "run": dry("terminal") },
            { "label": "Forget every saved display layout for this set of displays and start over", "icon": "close", "danger": true, "run": dry("danger") },
            { "label": "A row with no icon", "run": dry("plain") }
        ];
        for (let i = 1; i <= 24; i++) list.push({ "label": "Workspace " + i + " · 99+ windows", "icon": "grid", "detail": "Super " + (i % 10), "run": dry("ws" + i) });
        return list.concat([{ "rule": true }, { "label": "Settings…", "icon": "gear", "detail": "Super ,", "run": dry("settings") }]);
    }
    function items() {
        if (fixture === "stress") return stress();
        if (fixture === "empty") return [];
        return live();
    }
    function title() { return fixture === "stress" ? "Interstellar · HEADLESS-1 · a display with a long name the EDID reports, 3840×2160 @ 59.94 Hz" : ""; }

    function screenNamed(name) { return Quickshell.screens.find(s => s.name === name) || Shell.screenFor(Quickshell.screens); }
    function show(name, x, y) {
        const s = screenNamed(name);
        const m = menus.find(w => w.screen === s);
        if (!m) return false;
        for (const w of menus) if (w !== m) w.close();
        const at = x < 0 || y < 0 ? Qt.point(s.width / 2, s.height / 2) : Qt.point(x, y);
        m.popup(at, title(), items());
        openOn = m;
        return true;
    }
    function closeAll() { for (const w of menus) w.close(); }
    property var menus: []

    // Another panel opening (the launcher, Settings) takes over.
    Connections {
        target: Shell
        function onAnyOpenChanged() { if (Shell.anyOpen) root.closeAll(); }
    }

    IpcHandler {
        target: "desktop"
        // The menu at x, y on screen (screen coordinates); "" or an unknown
        // name is the focused screen, a negative x or y its middle.
        function menu(screen: string, x: int, y: int): void { root.show(screen, x, y); }
        function close(): void { root.closeAll(); }
        // Choose the open menu's row at index (0-based, rules count), as a click would.
        function choose(index: int): string {
            const m = root.openOn;
            if (!m || !m.open) return "not open";
            const it = m.shown[index];
            if (!m.usable(it)) return "not choosable";
            m.choose(index);
            return root.lastChosen;
        }
        // stress | empty; normal or anything else is the live menu (dry in the harness).
        function fixture(name: string): void { root.fixture = name === "stress" || name === "empty" ? name : ""; }
        function state(): string {
            const m = root.openOn;
            return JSON.stringify({
                "open": !!m && m.open, "screen": m && m.screen ? m.screen.name : "", "at": m ? [m.at.x, m.at.y] : [],
                "sheet": m ? [m.sheetX, m.sheetY, Math.round(m.sheetW), Math.round(m.sheetH)] : [],
                "current": m ? m.current : -1, "fixture": root.fixture, "chosen": root.lastChosen,
                "items": m ? m.shown.map(it => it.rule ? "—" : (it.label + (it.detail ? " [" + it.detail + "]" : "") + (it.disabled ? " (off)" : ""))) : []
            }, null, 1);
        }
    }

    Variants {
        model: Quickshell.screens
        ContextMenu {
            id: menu
            required property var modelData
            screen: modelData
            side: "below"
            layerName: "folio:desktop-menu"
            onChosen: (i, label) => root.lastChosen = label
            Component.onCompleted: root.menus = root.menus.concat([menu])
            Component.onDestruction: root.menus = root.menus.filter(w => w !== menu)
        }
    }
}
