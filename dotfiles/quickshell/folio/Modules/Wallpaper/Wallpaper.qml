import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// The living plate on every screen (Lumen: the sky): develops when the
// session starts, keeps its dither moving, dissolves to a new plate and bleeds
// in a new ink or mode. It also carries the look to niri: the Motion setting,
// so windows keep the same pace as the panels, the theme's window motion
// (Folio's windows print dot by dot, the look's own shaders; Lumen's glide),
// and the theme's color for the focus ring and borders.
Scope {
    id: root

    // Settings › Motion for windows: Gentle runs niri's animations twice as
    // fast, Still turns them off, Full leaves the look's as they are. niri
    // reads ~/.config/niri/folio-motion.kdl (included after the look and
    // DMS's colors) and reloads by itself; it is rewritten only when it changes.
    readonly property bool harness: !!Quickshell.env("FOLIO_HARNESS")
    readonly property string motionPath: harness
        ? (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/folio-motion.kdl"
        : Quickshell.env("HOME") + "/.config/niri/folio-motion.kdl"
    readonly property string motionKdl: {
        const m = Settings.get("motion");
        const body = m === "still" ? "animations {\n    off\n}\n"
                   : m === "gentle" ? "animations {\n    slowdown 0.5\n}\n" : "";
        return "// Written by Interstellar from Settings › Motion (" + (m || "full") + ") and the "
            + Theme.name + " theme.\n" + body + (Theme.prints ? "" : root.glide) + root.colorsKdl;
    }
    function hex(c) { const h = v => ("0" + Math.round(v * 255).toString(16)).slice(-2); return "#" + h(c.r) + h(c.g) + h(c.b); }
    // The focus ring and borders in the theme's color; quiet when unfocused.
    readonly property string colorsKdl: {
        const active = hex(Theme.ink), quiet = hex(Theme.mix(Theme.paper, Theme.tint, 0.3)), urgent = hex(Theme.error);
        const ring = "        active-color \"" + active + "\"\n        inactive-color \"" + quiet + "\"\n        urgent-color \"" + urgent + "\"\n";
        return "layout {\n    focus-ring {\n" + ring + "    }\n    border {\n" + ring + "    }\n}\n";
    }
    // Lumen's windows glide: in with a fade from 94 %, out with a fade to 96 %.
    readonly property string glide: "animations {\n"
        + "    window-open {\n        duration-ms 260\n        curve \"ease-out-expo\"\n        custom-shader r\"\n"
        + "            vec4 open_color(vec3 coords_geo, vec3 size_geo) {\n"
        + "                float p = niri_clamped_progress;\n"
        + "                vec3 c = vec3((coords_geo.xy - 0.5) / mix(0.94, 1.0, p) + 0.5, 1.0);\n"
        + "                if (c.x < 0.0 || c.x > 1.0 || c.y < 0.0 || c.y > 1.0) return vec4(0.0);\n"
        + "                return texture2D(niri_tex, (niri_geo_to_tex * c).st) * p;\n"
        + "            }\n        \"\n    }\n"
        + "    window-close {\n        duration-ms 180\n        curve \"ease-out-quad\"\n        custom-shader r\"\n"
        + "            vec4 close_color(vec3 coords_geo, vec3 size_geo) {\n"
        + "                float p = niri_clamped_progress;\n"
        + "                vec3 c = vec3((coords_geo.xy - 0.5) / mix(1.0, 0.96, p) + 0.5, 1.0);\n"
        + "                if (c.x < 0.0 || c.x > 1.0 || c.y < 0.0 || c.y > 1.0) return vec4(0.0);\n"
        + "                return texture2D(niri_tex, (niri_geo_to_tex * c).st) * (1.0 - p);\n"
        + "            }\n        \"\n    }\n}\n"
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
