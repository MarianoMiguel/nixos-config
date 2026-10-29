import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// The living plate on every screen: develops when the session starts, keeps
// its dither moving, dissolves to a new plate and bleeds in a new ink or mode.
// It also carries Folio's Motion setting to niri, so windows keep the same
// pace as Folio's panels.
Scope {
    id: root

    // Settings › Motion for windows: Gentle runs niri's animations twice as
    // fast, Still turns them off, Full leaves the look's as they are. niri
    // reads ~/.config/niri/folio-motion.kdl (included after the look) and
    // reloads by itself; it is rewritten only when it changes.
    readonly property bool harness: !!Quickshell.env("FOLIO_HARNESS")
    readonly property string motionPath: harness
        ? (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/folio-motion.kdl"
        : Quickshell.env("HOME") + "/.config/niri/folio-motion.kdl"
    readonly property string motionKdl: {
        const m = Settings.get("motion");
        const body = m === "still" ? "animations {\n    off\n}\n"
                   : m === "gentle" ? "animations {\n    slowdown 0.5\n}\n" : "";
        return "// Written by Folio from Settings › Motion (" + (m || "full") + ").\n" + body;
    }
    property string motionWritten: ""
    property bool motionRead: false
    function writeMotion() { if (motionRead && motionKdl !== motionWritten) { motionWritten = motionKdl; motionFile.setText(motionKdl); } }
    onMotionKdlChanged: writeMotion()
    FileView {
        id: motionFile
        path: root.motionPath
        printErrors: false
        atomicWrites: true
        onLoaded: { root.motionWritten = text(); root.motionRead = true; root.writeMotion(); }
        onLoadFailed: { root.motionRead = true; root.writeMotion(); }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            color: Theme.paper
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "folio:wallpaper"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            mask: Region {}

            Plate {
                anchors.fill: parent
                breathe: Art.breathe
            }
        }
    }
}
