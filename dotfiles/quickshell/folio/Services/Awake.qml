pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Keep awake: while on, an idle inhibitor stops the screen from dimming,
// locking or sleeping. The Idle module reads `on` as well. The inhibitor
// needs a mapped surface, so a 1 px transparent one exists only while on.
// Survives a shell restart.
Singleton {
    id: root

    property bool on: false
    function toggle() { set(!on); }
    function set(v) { on = v; file.setText(JSON.stringify({ "on": on })); }

    PanelWindow {
        id: holder
        visible: root.on
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        anchors { top: true; left: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "folio:awake"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}
    }
    IdleInhibitor {
        window: holder
        enabled: root.on
    }

    FileView {
        id: file
        path: Quickshell.statePath("awake.json")
        printErrors: false
        onLoaded: { try { root.on = JSON.parse(text()).on === true; } catch (e) {} }
    }
}
