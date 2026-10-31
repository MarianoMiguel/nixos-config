pragma Singleton
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Common

// Azure Folio's art: the catalog, the plate files and the plate in use.
// Plates load from the light render of each plate; the shader re-prints them
// in whatever ink and mode the desktop has.
//
// Your pictures: every JPEG, PNG or WebP in ~/Pictures/Folio is a plate of
// one more collection, "mine". azure-folio prints them (tools/azure-folio/
// pictures.py) into a store in the cache, in the same formats as the shipped
// plates, and this merges the store's catalog. The folder is watched, so a
// picture dropped in appears without a restart. They never leave the
// machine: the greeter has no home of the owner's and shows the shipped
// default plate instead. The harness keeps both in its runtime directory.
Singleton {
    id: root

    // The package's share dir, from the selection's image paths when present.
    readonly property string share: {
        const p = (Theme.selection.images && Theme.selection.images[0]) ? Theme.selection.images[0].desktop : "";
        const i = p.indexOf("/share/azure-folio/");
        return i > 0 ? p.slice(0, i + 19) : "/run/current-system/sw/share/azure-folio/";
    }
    property var catalog: ({ "collections": [] })
    FileView {
        path: root.share + "catalog.json"
        onLoaded: {
            try { root.catalog = JSON.parse(text()); } catch (e) { console.warn("Art: unreadable catalog", e); }
        }
    }

    // Your pictures: where they are and where their prints are kept.
    readonly property bool greeter: !!Quickshell.env("FOLIO_GREETER_STATE")
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string runtime: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string folder: Quickshell.env("AZURE_FOLIO_PICTURES")
        || (Sys.harness ? runtime + "/folio-pictures" : home + "/Pictures/Folio")
    readonly property string store: Quickshell.env("AZURE_FOLIO_PICTURES_STORE")
        || (Sys.harness ? runtime + "/folio-pictures-store" : (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/azure-folio/pictures")
    // The folder as people say it: ~/Pictures/Folio.
    readonly property string folderShown: home && folder.indexOf(home + "/") === 0 ? "~" + folder.slice(home.length) : folder
    property var mineDoc: ({})
    property bool mineRead: greeter          // the store's catalog was read (or found missing)
    property bool fixtureEmpty: false
    readonly property var mine: {
        const c = fixtureEmpty ? {} : (mineDoc.collection || {});
        const ok = v => Array.isArray(v) && v.length === 2 && v.every(n => typeof n === "number" && n >= 0 && n <= 1);
        const art = (Array.isArray(c.art) ? c.art : [])
            .filter(a => a && typeof a.id === "string" && /^mine-[0-9a-f]{16}$/.test(a.id))
            .map(a => ({ "id": a.id, "title": String(a.title || "Untitled"), "credit": "Your picture",
                         // The point the plate keeps in view, in the plate's own terms.
                         "desktopFocus": ok(a.plateFocus) ? a.plateFocus : ok(a.desktopFocus) ? a.desktopFocus : [0.5, 0.5] }));
        return { "id": "mine", "name": "Your pictures", "description": "Your own, printed in your ink", "user": true, "art": art };
    }
    readonly property int pending: fixtureEmpty ? 0 : (mineDoc.pending || 0)
    readonly property var skipped: fixtureEmpty ? [] : (mineDoc.skipped || [])
    readonly property bool scanning: scanner.running

    readonly property var plates: {
        const out = [];
        for (const c of root.collections)
            for (const a of c.art)
                // One language: the catalog's "Azure Folio · …" credits read "Folio · …".
                out.push({ "id": a.id, "title": a.title, "credit": (a.credit || "").replace(/^Azure Folio/, "Folio"), "focus": a.desktopFocus, "collection": c.id, "collectionName": c.name, "user": !!c.user });
        return out;
    }
    // The shipped collections, then yours while it has pictures.
    readonly property var collections: (root.catalog.collections || []).concat(root.mine.art.length ? [root.mine] : [])
    function plate(id) { return plates.find(p => p.id === id) || null; }
    function focus(id) { const p = plate(id); return p && p.focus ? Qt.vector2d(p.focus[0], p.focus[1]) : Qt.vector2d(0.5, 0.5); }

    // The desktop's plate: the selection's collection and art index.
    // How much the plate's dither keeps moving (Settings "plates.breathe").
    // On battery it holds still unless asked otherwise: a moving plate
    // re-renders the wallpaper, and every blurred panel over it, 9 times a second.
    readonly property real breathe: (Settings.get("plates.breathe") || 0)
        * (Battery.onBattery && Settings.get("plates.breatheOnBattery") !== true ? 0 : 1)
    readonly property string current: {
        const c = collections.find(x => x.id === Theme.selection.collection);
        // Your pictures, before their catalog is read: nothing yet, rather
        // than a shipped plate that would dissolve away a moment later.
        if (!c) return Theme.selection.collection === "mine" && !mineRead ? "" : "dore-nightfall";
        return c.art[Math.max(0, Math.min(Theme.selection.art || 0, c.art.length - 1))].id;
    }
    // Your pictures' ids start with "mine-" (pictures.py); theirs live in the store.
    function base(id) { return id.indexOf("mine-") === 0 ? "file://" + store + "/art/" : "file://" + share + "art/"; }
    function mask(id) { return id ? base(id) + id + "/azure-light-desktop.png" : ""; }
    function portrait(id) { return id ? base(id) + id + "/azure-light-portrait.png" : ""; }

    // ---------------------------------------------------------- your pictures
    FileView {
        id: mineFile
        path: root.greeter ? "" : root.store + "/catalog.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.mineDoc = JSON.parse(text()); } catch (e) { root.mineDoc = {}; }
            root.mineRead = true; root.mineMissing = false;
        }
        onLoadFailed: { root.mineDoc = {}; root.mineRead = true; root.mineMissing = true; }
    }
    // A catalog that was not there is not watched yet: read it while the
    // first scan prints (each picture appears as it is printed) and after.
    property bool mineMissing: false
    Timer { interval: 2000; repeat: true; running: root.mineMissing && scanner.running; onTriggered: mineFile.reload() }

    // Read the folder again: new pictures print, removed ones are forgotten.
    // One scan at a time; asks made while one runs make one more.
    property bool again: false
    property bool openAfter: false
    function scan(create) {
        if (greeter) return;
        if (scanner.running) { again = true; return; }
        scanner.command = ["azure-folio", "pictures"].concat(create ? ["--create"] : []);
        scanner.running = true;
    }
    // "Open folder": made first if it is not there yet.
    function openFolder() {
        openAfter = true;
        scan(true);
    }
    Process {
        id: scanner
        environment: ({ "AZURE_FOLIO_PICTURES": root.folder, "AZURE_FOLIO_PICTURES_STORE": root.store })
        stdout: StdioCollector {
            id: scanOut
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) {}
                // Files still arriving (a copy in progress) are read once they settle.
                if (r.arriving > 0) settle.restart();
            }
        }
        stderr: StdioCollector { id: scanErr }
        onExited: code => {
            if (code !== 0) console.warn("Art: azure-folio pictures failed:", scanErr.text.trim());
            if (root.mineMissing) mineFile.reload();
            if (root.openAfter) { root.openAfter = false; Apps.open(root.folder); }
            if (root.again) { root.again = false; root.scan(false); }
        }
    }
    Timer { id: settle; interval: 2500; onTriggered: root.scan(false) }
    Timer { id: debounce; interval: 700; onTriggered: root.scan(false) }
    // The folder, watched while it exists: added, removed and renamed files.
    FolderListModel {
        id: watch
        folder: !root.greeter && root.mineDoc.present ? "file://" + root.folder : ""
        showDirs: false
        showHidden: false
        onCountChanged: debounce.restart()
        onRowsInserted: debounce.restart()
        onRowsRemoved: debounce.restart()
        onDataChanged: debounce.restart()
    }
    Component.onCompleted: scan(false)

    IpcHandler {
        target: "pictures"
        // Tests: "empty" shows no pictures; "normal" the folder's.
        function fixture(name: string): void { root.fixtureEmpty = name === "empty"; }
        function scan(): void { root.scan(false); }
        function open(): void { root.openFolder(); }
        function state(): string { return JSON.stringify({ "folder": root.folder, "store": root.store, "pictures": root.mine.art.length, "pending": root.pending, "skipped": root.skipped, "scanning": root.scanning, "current": root.current }); }
    }
}
