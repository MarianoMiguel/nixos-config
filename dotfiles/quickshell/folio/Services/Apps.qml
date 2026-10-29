pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Installed applications (desktop entries), launched with their actions.
// Search ranks by match quality and by how often each app is launched.
Singleton {
    id: root

    readonly property var all: DesktopEntries.applications.values.filter(e => !e.noDisplay).slice().sort((a, b) => a.name.localeCompare(b.name))
    property var usage: ({})

    function launch(entry, action) {
        if (action) action.execute(); else entry.execute();
        const u = Object.assign({}, usage);
        u[entry.id] = (u[entry.id] || 0) + 1;
        usage = u;
        file.setText(JSON.stringify(usage));
    }
    function score(entry, q) {
        const name = (entry.name || "").toLowerCase();
        const words = [entry.genericName, entry.comment].concat(entry.keywords || []).join(" ").toLowerCase();
        let s = 0;
        if (name === q) s = 100;
        else if (name.startsWith(q)) s = 80;
        else if (name.split(/[\s-]/).some(w => w.startsWith(q))) s = 60;
        else if (name.indexOf(q) >= 0) s = 40;
        else if (words.indexOf(q) >= 0) s = 20;
        else {
            let i = 0;
            for (const ch of name) if (ch === q[i]) i++;
            s = i === q.length ? 10 : 0;
        }
        return s ? s + Math.min(20, (usage[entry.id] || 0) * 2) : 0;
    }
    function search(query, limit) {
        const q = (query || "").trim().toLowerCase();
        if (!q) return all.slice().sort((a, b) => (usage[b.id] || 0) - (usage[a.id] || 0)).slice(0, limit || 8);
        return all.map(e => ({ "e": e, "s": score(e, q) })).filter(x => x.s > 0).sort((a, b) => b.s - a.s).slice(0, limit || 8).map(x => x.e);
    }

    FileView {
        id: file
        path: Quickshell.statePath("app-usage.json")
        printErrors: false
        onLoaded: { try { root.usage = JSON.parse(text()); } catch (e) {} }
    }
}
