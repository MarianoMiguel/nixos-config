pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Folio's tokens: the same names and values as workshop/studies/_kit/folio.css.
// Mode, ink and plate come from Folio's selection (tools/azure-folio), which
// the Appearance panel and the Folio picker write; every change glides.
Singleton {
    id: root

    readonly property string selectionPath: Quickshell.env("HOME") + "/.local/state/nixos-config/azure-folio/selection.json"
    property var selection: ({})
    // Tests and previews can pin a mode or ink without touching the selection.
    property string forceMode: Quickshell.env("FOLIO_MODE") || ""
    property string forceInk: Quickshell.env("FOLIO_INK") || ""

    FileView {
        path: root.selectionPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.selection = JSON.parse(text()); } catch (e) { console.warn("Theme: unreadable selection", e); }
        }
    }

    readonly property string mode: forceMode || selection.mode || "light"
    readonly property string inkName: forceInk || selection.ink || "azure"
    readonly property bool dark: mode === "dark"

    readonly property var inks: ({
        "azure": ["#214c94", "#adc7ed"],
        "cobalt": ["#244fb8", "#9dbbfa"],
        "slate": ["#35556e", "#adc3d2"]
    })

    function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t); }

    // The four sources; everything else derives from them.
    property color paper: dark ? "#101d33" : "#f7f4e9"
    property color ink: (inks[inkName] || inks.azure)[dark ? 1 : 0]
    property color text: dark ? "#e4e9f0" : "#1a2740"
    property color sheetBase: dark ? "#182a49" : "#fffdf6"
    Behavior on paper { ColorAnimation { duration: root.tPage; easing.type: Easing.OutCubic } }
    Behavior on ink { ColorAnimation { duration: root.tPage; easing.type: Easing.OutCubic } }
    Behavior on text { ColorAnimation { duration: root.tPage; easing.type: Easing.OutCubic } }
    Behavior on sheetBase { ColorAnimation { duration: root.tPage; easing.type: Easing.OutCubic } }

    // Higher contrast (Settings › Accessibility): secondary text nearer the
    // text, firmer hairlines, wells and sheets more opaque.
    readonly property bool high: Settings.get("contrast") === "high"
    readonly property color text2: mix(text, paper, high ? 0.16 : 0.34)
    readonly property color text3: mix(text, paper, high ? 0.3 : 0.56)
    readonly property color wash: mix(paper, ink, 0.07)
    readonly property color well: rgba(ink, high ? 0.13 : 0.09)
    readonly property color wellStrong: rgba(ink, high ? 0.24 : 0.16)
    readonly property color rule: rgba(ink, high ? 0.42 : 0.16)
    readonly property color ruleStrong: rgba(ink, high ? 0.62 : 0.30)
    // Text and icons on an ink fill. (Not "onInk": QML reads on+Capital as a handler.)
    readonly property color inkText: paper
    readonly property color sheet: rgba(sheetBase, high ? 0.95 : 0.74)
    readonly property color sheetStrong: rgba(sheetBase, 0.93)
    readonly property color highlight: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.6)
    readonly property color shade: dark ? "#02060e" : "#101d33"
    // The island and the dock's dark tiles: deep ink in both modes.
    readonly property color island: mix(Qt.color("#0b1424"), Qt.color((inks[inkName] || inks.azure)[0]), 0.46)
    readonly property color islandText: "#eef2f8"
    readonly property color islandInk: "#adc7ed"
    // Reds that read on the island's deep ink: the recording dot, alert text.
    readonly property color islandAlert: "#f07b70"
    readonly property color islandAlertText: "#f4a49a"
    readonly property color success: dark ? "#8cc5a3" : mix(Qt.color("#3f7d5c"), ink, 0.2)
    readonly property color warning: dark ? "#e3b267" : "#b07a26"
    readonly property color error: dark ? "#f09088" : "#b4473f"

    // Shape. Radii nest: an inner corner is the outer one minus the padding
    // between them, so curves stay concentric (inner()).
    readonly property real rXs: 6
    readonly property real rS: 10
    readonly property real rM: 14
    readonly property real rL: 20
    readonly property real rXl: 28
    readonly property real rWindow: 14
    function inner(outer, pad) { return Math.max(4, outer - pad); }

    // Type
    readonly property string ui: "Inter"
    readonly property string mono: "IBM Plex Mono"
    readonly property string hero: "Jacquard 24"
    // Text size (Settings › Accessibility) scales every type token.
    readonly property real textScale: Math.max(0.9, Math.min(1.6, +Settings.get("text.scale") || 1))
    readonly property real fsCap: 10.5 * textScale
    readonly property real fsS: 12.5 * textScale
    readonly property real fsM: 13.5 * textScale
    readonly property real fsL: 16 * textScale
    readonly property real fsXl: 22 * textScale

    // Motion. Durations for eased moves; springs (Motion.qml) for anything
    // that can be interrupted, so retargeting keeps its velocity.
    // Scaled by Settings' motion level (full, gentle, still).
    readonly property real motion: Settings.motion
    readonly property int tPress: Math.round(120 * motion)
    readonly property int tQuick: Math.round(180 * motion)
    readonly property int tPanel: Math.round(320 * motion)
    readonly property int tPage: Math.round(520 * motion)
    readonly property int tDevelop: Math.round(1100 * motion)
    readonly property int stagger: Math.round(34 * motion)
}
