pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// niri through its JSON event stream: workspaces, windows, focus, keyboard
// layouts and the overview. Without niri (the harness runs sway) all of it
// stays empty and actions do nothing.
Singleton {
    id: root

    readonly property bool available: (Quickshell.env("NIRI_SOCKET") || "") !== ""
    property var workspaces: []
    property var windows: ({})
    property int focusedWindowId: -1
    property var layouts: []
    property int layoutIndex: 0
    property bool overview: false

    // niri re-read its config (failed: it kept the previous one).
    signal configLoaded(bool failed)

    readonly property var focusedWindow: windows[focusedWindowId] || null
    readonly property string layoutName: layouts[layoutIndex] || ""
    function workspacesOn(output) { return workspaces.filter(w => w.output === output).sort((a, b) => a.idx - b.idx); }
    function windowsOn(workspaceId) { return Object.values(windows).filter(w => w.workspace_id === workspaceId); }

    function action(args) { if (available) Quickshell.execDetached(["niri", "msg", "action"].concat(args)); }
    function focusWorkspace(ws) { action(["focus-workspace", String(ws.idx)]); }
    function focusWindow(id) { action(["focus-window", "--id", String(id)]); }
    function closeWindow(id) { action(["close-window", "--id", String(id)]); }
    function quit() { action(["quit", "--skip-confirmation"]); }

    Process {
        id: stream
        running: root.available
        command: ["niri", "msg", "--json", "event-stream"]
        stdout: SplitParser { onRead: line => root.handle(line) }
        onExited: if (root.available) restartTimer.start()
    }
    Timer { id: restartTimer; interval: 1000; onTriggered: stream.running = true }

    function handle(line) {
        let ev;
        try { ev = JSON.parse(line); } catch (e) { return; }
        if (ev.WorkspacesChanged) {
            workspaces = ev.WorkspacesChanged.workspaces;
        } else if (ev.WorkspaceActivated) {
            const a = ev.WorkspaceActivated;
            const output = (workspaces.find(w => w.id === a.id) || {}).output;
            workspaces = workspaces.map(w => Object.assign({}, w, {
                "is_active": w.output === output ? w.id === a.id : w.is_active,
                "is_focused": a.focused ? w.id === a.id : w.is_focused
            }));
        } else if (ev.WorkspaceActiveWindowChanged) {
            const a = ev.WorkspaceActiveWindowChanged;
            workspaces = workspaces.map(w => w.id === a.workspace_id ? Object.assign({}, w, { "active_window_id": a.active_window_id }) : w);
        } else if (ev.WindowsChanged) {
            const map = {};
            for (const w of ev.WindowsChanged.windows) { map[w.id] = w; if (w.is_focused) focusedWindowId = w.id; }
            windows = map;
        } else if (ev.WindowOpenedOrChanged) {
            const w = ev.WindowOpenedOrChanged.window;
            const map = Object.assign({}, windows);
            map[w.id] = w;
            windows = map;
            if (w.is_focused) focusedWindowId = w.id;
        } else if (ev.WindowClosed) {
            const map = Object.assign({}, windows);
            delete map[ev.WindowClosed.id];
            windows = map;
            if (focusedWindowId === ev.WindowClosed.id) focusedWindowId = -1;
        } else if (ev.WindowFocusChanged) {
            focusedWindowId = ev.WindowFocusChanged.id === null ? -1 : ev.WindowFocusChanged.id;
        } else if (ev.KeyboardLayoutsChanged) {
            layouts = ev.KeyboardLayoutsChanged.keyboard_layouts.names;
            layoutIndex = ev.KeyboardLayoutsChanged.keyboard_layouts.current_idx;
        } else if (ev.KeyboardLayoutSwitched) {
            layoutIndex = ev.KeyboardLayoutSwitched.idx;
        } else if (ev.OverviewOpenedOrClosed) {
            overview = ev.OverviewOpenedOrClosed.is_open;
        } else if (ev.ConfigLoaded) {
            configLoaded(!!ev.ConfigLoaded.failed);
        }
    }
}
