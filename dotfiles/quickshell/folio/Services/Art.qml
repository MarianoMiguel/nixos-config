pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// Azure Folio's art: the catalog, the plate files and the plate in use.
// Plates load from the light render of each plate; the shader re-prints them
// in whatever ink and mode the desktop has.
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

    readonly property var plates: {
        const out = [];
        for (const c of root.catalog.collections || [])
            for (const a of c.art)
                // One language: the catalog's "Azure Folio · …" credits read "Folio · …".
                out.push({ "id": a.id, "title": a.title, "credit": (a.credit || "").replace(/^Azure Folio/, "Folio"), "focus": a.desktopFocus, "collection": c.id, "collectionName": c.name });
        return out;
    }
    readonly property var collections: root.catalog.collections || []
    function plate(id) { return plates.find(p => p.id === id) || null; }
    function focus(id) { const p = plate(id); return p ? Qt.vector2d(p.focus[0], p.focus[1]) : Qt.vector2d(0.5, 0.5); }

    // The desktop's plate: the selection's collection and art index.
    // How much the plate's dither keeps moving (Settings "plates.breathe").
    // On battery it holds still unless asked otherwise: a moving plate
    // re-renders the wallpaper, and every blurred panel over it, 9 times a second.
    readonly property real breathe: (Settings.get("plates.breathe") || 0)
        * (Battery.onBattery && Settings.get("plates.breatheOnBattery") !== true ? 0 : 1)
    readonly property string current: {
        const c = collections.find(x => x.id === Theme.selection.collection);
        if (!c) return "dore-nightfall";
        return c.art[Math.max(0, Math.min(Theme.selection.art || 0, c.art.length - 1))].id;
    }
    function mask(id) { return id ? "file://" + share + "art/" + id + "/azure-light-desktop.png" : ""; }
    function portrait(id) { return id ? "file://" + share + "art/" + id + "/azure-light-portrait.png" : ""; }
}
