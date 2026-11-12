pragma Singleton
import QtQuick
import Quickshell
import qs.Common

// UI state shared between modules: which panels are open and where. Modules
// bind to it; their IPC handlers and keybinds change it. Opening one panel
// closes the others, so the right edge only ever has one thing on it.
Singleton {
    id: root

    property bool sidebarOpen: false
    property string sidebarSection: ""
    property bool launcherOpen: false
    property string launcherQuery: ""
    property bool settingsOpen: false
    property string settingsPage: ""        // a page or a section of one: "displays", "wallpaper"
    property bool playerOpen: false
    property bool powerOpen: false

    readonly property bool anyOpen: sidebarOpen || launcherOpen || settingsOpen || playerOpen || powerOpen

    function closeAll() {
        sidebarOpen = false; launcherOpen = false; settingsOpen = false; playerOpen = false; powerOpen = false;
    }
    function toggleSidebar(section) {
        if (sidebarOpen && (!section || section === sidebarSection)) { sidebarOpen = false; return; }
        closeAll();
        sidebarSection = section || "";
        sidebarOpen = true;
    }
    function openLauncher(query) { closeAll(); launcherQuery = query || ""; launcherOpen = true; }
    function toggleLauncher() { if (launcherOpen) closeAll(); else openLauncher(""); }
    // Settings stays open when it is already (a link inside it changes the page).
    function openSettings(page) {
        sidebarOpen = false; launcherOpen = false; playerOpen = false; powerOpen = false;
        settingsPage = page || "";
        settingsOpen = true;
    }
    function toggleSettings(page) { if (settingsOpen && (!page || page === settingsPage)) closeAll(); else openSettings(page); }
    function openAppearance(section) { openSettings(section || "appearance"); }
    function togglePlayer() { const open = !playerOpen; closeAll(); playerOpen = open; }
    function togglePower() { const open = !powerOpen; closeAll(); powerOpen = open; }

    // The login score (workshop/studies/motion): when the session starts each
    // surface arrives at its moment. delay(part) is how long a surface waits
    // before its entrance: zero once the moment has passed or with the score off.
    readonly property real startedAt: Date.now()
    readonly property var score: ({ "wallpaper": 0, "bar": 520, "island": 640, "dock": 700, "toasts": 1600 })
    function delay(part) {
        if (Settings.get("login.score") === false) return 0;
        return Math.max(0, startedAt + (score[part] || 0) - Date.now());
    }

    // Panels open on the output with the focused workspace, else the first.
    readonly property string focusedOutput: (Niri.workspaces.find(w => w.is_focused) || {}).output || ""
    function screenFor(screens) {
        for (const s of screens) if (s.name === focusedOutput) return s;
        return screens.length ? screens[0] : null;
    }
}
