pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Default apps: which app opens web links, mail, folders, a terminal, text,
// images, video, music and PDFs. The current default comes from
// `xdg-mime query default` (the terminal from xdg-terminal-exec); candidates
// are the desktop entries whose MimeType lists the kind's type (Quickshell's
// DesktopEntries has no MimeType, so the files are read for it; names and
// icons come from DesktopEntries). Setting runs `xdg-mime default` through
// Sys (dry-run in the harness) and writes ~/.config/mimeapps.list; when Home
// Manager owns that file (a link into the Nix store) everything is read-only.
Singleton {
    id: root

    // key: the type asked for the current default; types: what a choice sets
    // (all of them for the browser, otherwise those the app lists itself).
    readonly property var kinds: [
        { "id": "browser", "title": "Web browser", "icon": "globe", "what": "Web links and pages", "key": "x-scheme-handler/https", "all": true,
          "types": ["x-scheme-handler/http", "x-scheme-handler/https", "text/html", "application/xhtml+xml"] },
        { "id": "mail", "title": "Mail", "icon": "mail", "what": "Email links", "key": "x-scheme-handler/mailto", "types": ["x-scheme-handler/mailto"] },
        { "id": "files", "title": "Files", "icon": "folder", "what": "Folders", "key": "inode/directory", "types": ["inode/directory"] },
        { "id": "terminal", "title": "Terminal", "icon": "terminal", "what": "Apps that open a terminal (xdg-terminal-exec)", "terminal": true, "types": [] },
        { "id": "editor", "title": "Text editor", "icon": "pencil", "what": "Plain text", "key": "text/plain", "types": ["text/plain"] },
        { "id": "images", "title": "Images", "icon": "image", "what": "PNG, JPEG, GIF, WebP and more", "key": "image/png",
          "types": ["image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/tiff", "image/svg+xml", "image/avif", "image/heic"] },
        { "id": "video", "title": "Video", "icon": "play", "what": "MP4, MKV, WebM and more", "key": "video/mp4",
          "types": ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime", "video/x-msvideo", "video/mpeg", "video/ogg"] },
        { "id": "music", "title": "Music", "icon": "music", "what": "MP3, FLAC, Ogg and more", "key": "audio/mpeg",
          "types": ["audio/mpeg", "audio/flac", "audio/x-flac", "audio/ogg", "audio/x-vorbis+ogg", "audio/opus", "audio/mp4", "audio/aac", "audio/x-wav", "audio/wav"] },
        { "id": "pdf", "title": "PDF", "icon": "note", "what": "PDF documents", "key": "application/pdf", "types": ["application/pdf"] }
    ]
    function kind(id) { return kinds.find(k => k.id === id) || null; }

    property var current: ({})          // kind -> desktop id, as the system says
    property var chosen: ({})           // kind -> desktop id chosen here, until the system agrees (dry-run: for good)
    property var handlers: ({})         // type -> desktop ids that list it
    property var typesOf: ({})          // desktop id -> the types it lists
    property string mimeappsTarget: ""
    property string terminalsTarget: ""
    property bool loading: false
    property string open: ""            // the chooser open on the page
    property var fx: null

    readonly property bool managed: fx ? !!fx.managed : mimeappsTarget.indexOf("/nix/store/") === 0
    readonly property bool terminalManaged: fx ? !!fx.managed : terminalsTarget.indexOf("/nix/store/") === 0
    function readOnly(k) { return k.terminal ? terminalManaged : managed; }

    // What the page shows: [{ kind, current: app | null, candidates: [app] }],
    // app = { id, name, icon, generic }.
    readonly property var rows: fx ? fx.rows : kinds.map(k => row(k, DesktopEntries.applications.values))
    function row(k, entries) {
        const id = chosen[k.id] || current[k.id] || "";
        const ids = k.terminal
            ? entries.filter(e => (e.categories || []).indexOf("TerminalEmulator") >= 0).map(e => e.id + ".desktop")
            : (handlers[k.key] || []);
        const seen = {};
        const cands = [];
        for (const i of ids) {
            const a = info(i);
            if (!a || seen[a.id] || (a.hidden && a.id !== id)) continue;
            seen[a.id] = true;
            cands.push(a);
        }
        let cur = id ? cands.find(a => a.id === id) || null : null;
        if (id && !cur) { cur = info(id) || { "id": id, "name": pretty(id), "icon": "", "generic": "" }; cands.push(cur); }
        cands.sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
        return { "kind": k, "current": cur, "candidates": cands };
    }
    function info(id) {
        const bare = id.replace(/\.desktop$/, "");
        const e = DesktopEntries.byId(bare);
        if (!e) return null;
        return { "id": bare + ".desktop", "name": e.name || pretty(id), "icon": e.icon || "", "generic": e.genericName || "", "hidden": !!e.noDisplay };
    }
    function pretty(id) {
        const tail = id.replace(/\.desktop$/, "").split(".").pop() || id;
        return tail.charAt(0).toUpperCase() + tail.slice(1);
    }

    // ------------------------------------------------------------ reading
    function refresh() { if (!fx) { loading = true; scan.running = false; scan.running = true; } }
    Component.onCompleted: refresh()
    Timer { id: refreshLater; interval: 700; onTriggered: root.refresh() }

    // One line per fact, tab-separated: where the lists resolve, the default
    // for each type asked, the terminal, and every entry's MimeType line.
    readonly property string scanScript: [
        "cfg=${XDG_CONFIG_HOME:-$HOME/.config}",
        "printf 'mimeapps\\t%s\\n' \"$(readlink -f \"$cfg/mimeapps.list\" 2>/dev/null)\"",
        "printf 'terminals\\t%s\\n' \"$(readlink -f \"$cfg/xdg-terminals.list\" 2>/dev/null)\"",
        "for t in \"$@\"; do printf 'default\\t%s\\t%s\\n' \"$t\" \"$(xdg-mime query default \"$t\" 2>/dev/null)\"; done",
        "printf 'terminal\\t%s\\n' \"$(xdg-terminal-exec --print-id 2>/dev/null)\"",
        "IFS=:",
        "for d in ${XDG_DATA_HOME:-$HOME/.local/share} ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do",
        "  [ -d \"$d/applications\" ] || continue",
        "  (cd \"$d/applications\" && grep -R -m1 --include='*.desktop' '^MimeType=' . 2>/dev/null) | sed 's/^/mime\\t/'",
        "done"
    ].join("\n")
    Process {
        id: scan
        command: ["sh", "-c", root.scanScript, "sh"].concat(root.kinds.filter(k => k.key).map(k => k.key))
        stdout: StdioCollector {
            onStreamFinished: {
                const cur = {}, handlers = {}, types = {}, byType = {};
                for (const line of text.split("\n")) {
                    const p = line.split("\t");
                    if (p[0] === "mimeapps") root.mimeappsTarget = (p[1] || "").trim();
                    else if (p[0] === "terminals") root.terminalsTarget = (p[1] || "").trim();
                    else if (p[0] === "default") byType[p[1]] = (p[2] || "").trim();
                    else if (p[0] === "terminal") cur.terminal = (p[1] || "").split(":")[0].trim();
                    else if (p[0] === "mime") {
                        const rest = p.slice(1).join("\t");
                        const at = rest.indexOf(":MimeType=");
                        if (at < 0) continue;
                        const id = rest.slice(0, at).replace(/^\.\//, "").replace(/\//g, "-");
                        if (types[id]) continue;            // the first directory wins
                        types[id] = rest.slice(at + 10).split(";").map(s => s.trim()).filter(s => s);
                        for (const t of types[id]) (handlers[t] = handlers[t] || []).push(id);
                    }
                }
                for (const k of root.kinds) if (k.key) cur[k.id] = byType[k.key] || "";
                root.handlers = handlers;
                root.typesOf = types;
                root.current = cur;
                // A choice stays shown until the system agrees with it.
                const c = Object.assign({}, root.chosen);
                for (const k in c) if (c[k] === cur[k]) delete c[k];
                root.chosen = c;
                root.loading = false;
            }
        }
    }

    // ------------------------------------------------------------ choosing
    function choose(kindId, id) {
        const k = kind(kindId);
        open = "";
        if (!k || !id) return;
        if (fx) {
            const r = fx.rows.map(x => x.kind.id !== kindId ? x : Object.assign({}, x, { "current": x.candidates.find(a => a.id === id) || x.current }));
            fx = Object.assign({}, fx, { "rows": r });
            return;
        }
        if (readOnly(k)) return;
        if (k.terminal) {
            Sys.run(["sh", "-c", "d=${XDG_CONFIG_HOME:-$HOME/.config}; mkdir -p \"$d\" && printf '%s\\n' \"$1\" > \"$d/xdg-terminals.list\"", "sh", id]);
        } else {
            const lists = typesOf[id] || [];
            const types = k.all ? k.types : [k.key].concat(k.types.filter(t => t !== k.key && lists.indexOf(t) >= 0));
            Sys.run(["xdg-mime", "default", id].concat(types));
        }
        const c = Object.assign({}, chosen);
        c[kindId] = id;
        chosen = c;
        refreshLater.restart();
    }

    // ------------------------------------------------------------ fixtures
    function makeFixture(name) {
        const A = (id, n, icon, generic) => ({ "id": id + ".desktop", "name": n, "icon": icon, "generic": generic || "" });
        const sets = {
            "browser": [A("google-chrome", "Google Chrome", "google-chrome", "Web Browser"), A("firefox", "Firefox", "firefox", "Web Browser"), A("brave-browser", "Brave Web Browser", "brave-browser", "Web Browser"), A("chromium-browser", "Chromium", "chromium", "Web Browser")],
            "mail": [A("thunderbird", "Thunderbird", "thunderbird", "Mail Client"), A("org.gnome.Geary", "Geary", "org.gnome.Geary", "Email")],
            "files": [A("org.gnome.Nautilus", "Files", "org.gnome.Nautilus", "File Manager"), A("org.kde.dolphin", "Dolphin", "system-file-manager", "File Manager")],
            "terminal": [A("com.mitchellh.ghostty", "Ghostty", "com.mitchellh.ghostty", "Terminal"), A("Alacritty", "Alacritty", "Alacritty", "Terminal"), A("kitty", "kitty", "kitty", "Terminal emulator")],
            "editor": [A("org.gnome.TextEditor", "Text Editor", "org.gnome.TextEditor", "Text Editor"), A("org.kde.kate", "Kate", "kate", "Advanced Text Editor"), A("nvim", "Neovim", "nvim", "Text Editor"), A("code", "Visual Studio Code", "vscode", "Text Editor")],
            "images": [A("org.gnome.Loupe", "Image Viewer", "org.gnome.Loupe", "Image Viewer"), A("gimp", "GNU Image Manipulation Program", "gimp", "Image Editor"), A("org.kde.krita", "Krita", "krita", "Digital Painting")],
            "video": [A("io.github.celluloid_player.Celluloid", "Celluloid", "io.github.celluloid_player.Celluloid", "Video Player"), A("vlc", "VLC media player", "vlc", "Media player"), A("mpv", "mpv Media Player", "mpv", "Multimedia player")],
            "music": [A("io.bassi.Amberol", "Amberol", "io.bassi.Amberol", "Music Player"), A("org.gnome.Rhythmbox3", "Rhythmbox", "org.gnome.Rhythmbox3", "Music Player"), A("vlc", "VLC media player", "vlc", "Media player")],
            "pdf": [A("org.gnome.Papers", "Papers", "org.gnome.Papers", "Document Viewer"), A("firefox", "Firefox", "firefox", "Web Browser"), A("org.kde.okular", "Okular", "okular", "Document Viewer")]
        };
        const pick = { "browser": 0, "mail": -1, "files": 0, "terminal": 0, "editor": 1, "images": 0, "video": 1, "music": 0, "pdf": 0 };
        const rows = kinds.map(k => {
            if (name === "empty") return { "kind": k, "current": null, "candidates": [] };
            let c = sets[k.id].slice();
            let cur = pick[k.id] >= 0 ? c[pick[k.id]] : null;
            if (name === "stress") {
                const long = A("org.example." + k.id + ".Long", c[0].name + " — Flatpak (org.freedesktop.Platform 24.08, user installation, beta branch)", "", c[0].generic);
                for (let i = 0; i < 18; i++) c.push(A("org.example." + k.id + i, c[i % 3 % c.length].name + " " + (i + 2) + (i % 4 === 0 ? " (Wine, Proton Experimental, with the 32-bit compatibility runtime)" : ""), i % 2 ? c[i % c.length].icon : "", ""));
                c.push(long);
                cur = long;
            }
            c.sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
            return { "kind": k, "current": cur, "candidates": c };
        });
        return { "rows": rows, "managed": name === "managed" };
    }

    IpcHandler {
        target: "apps"
        // normal | stress | empty | managed (read-only); "" (anything else) is live.
        function fixture(name: string): void {
            root.open = "";
            root.fx = ["normal", "stress", "empty", "managed"].indexOf(name) >= 0 ? root.makeFixture(name) : null;
            if (!root.fx) root.refresh();
        }
        // Open a kind's chooser on the page (browser, mail, files, terminal,
        // editor, images, video, music, pdf); "" closes it.
        function open(kind: string): void { root.open = kind; }
        // Set a default (dry-run in the harness): choose browser firefox.desktop
        function choose(kind: string, id: string): void { root.choose(kind, id); }
        function refresh(): void { root.refresh(); }
        function state(): string {
            return JSON.stringify({
                "fixture": !!root.fx, "managed": root.managed, "terminalManaged": root.terminalManaged, "mimeapps": root.mimeappsTarget,
                "rows": root.rows.map(r => ({ "kind": r.kind.id, "current": r.current ? r.current.id : "", "candidates": r.candidates.map(a => a.id) }))
            });
        }
    }
}
