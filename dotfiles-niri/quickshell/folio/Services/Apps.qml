pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Installed applications (desktop entries), launched with their actions.
// Search ranks by match quality and by how often each app is launched.
//
// Every app starts in a transient scope of its own (app-folio-<id>-<random>
// in app.slice, systemd's naming for launched apps), never in
// folio-shell.service: a shell restart, crash or switch to DMS leaves the apps
// running, and their CPU is not counted as the shell's. Launches go through
// Sys.run, so the harness records the command instead.
Singleton {
    id: root

    readonly property var all: DesktopEntries.applications.values.filter(e => !e.noDisplay).slice().sort((a, b) => a.name.localeCompare(b.name))
    property var usage: ({})

    function launch(entry, action) {
        // The Exec line as Quickshell parsed it (field codes dropped), as execute() runs it.
        let cmd = Array.from((action || entry).command || []);
        if (!cmd.length) return;
        if (entry.workingDirectory) cmd = ["env", "-C", entry.workingDirectory].concat(cmd);
        Sys.run(scoped(entry.id, cmd));
        const u = Object.assign({}, usage);
        u[entry.id] = (u[entry.id] || 0) + 1;
        usage = u;
        file.setText(JSON.stringify(usage));
    }
    // A file or URL in its default app, scoped like a launch.
    function open(target) { return Sys.run(scoped("xdg-open", ["xdg-open", target])); }
    // cmd wrapped to run in a new scope named for id. PartOf the graphical
    // session: apps still end with the session, as they did inside the shell.
    function scoped(id, cmd) {
        const rand = Math.floor(Math.random() * 0x100000000).toString(16).padStart(8, "0");
        return ["systemd-run", "--user", "--scope", "--quiet", "--collect", "--slice=app.slice",
                "--property=PartOf=graphical-session.target", "--property=After=graphical-session.target",
                "--unit=app-folio-" + unitEscape(id).slice(0, 200) + "-" + rand + ".scope", "--"].concat(cmd);
    }
    // systemd-escape: a unit name keeps [A-Za-z0-9:_.] (no leading dot);
    // "-" separates its parts, so that and anything else becomes \xNN (UTF-8).
    function unitEscape(s) {
        let out = "";
        for (const ch of String(s || "app")) {
            if (/[A-Za-z0-9:_]/.test(ch) || (ch === "." && out !== "")) { out += ch; continue; }
            const utf8 = encodeURIComponent(ch);          // "%E2%80%94"; "-", "~" and a few more come back as is
            out += utf8 === ch ? "\\x" + ch.charCodeAt(0).toString(16).padStart(2, "0")
                               : utf8.replace(/%([0-9A-F]{2})/g, (m, h) => "\\x" + h.toLowerCase());
        }
        return out;
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
