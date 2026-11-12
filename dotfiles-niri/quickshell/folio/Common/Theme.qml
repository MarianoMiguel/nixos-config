pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Looks.js" as Looks

// Interstellar's tokens. A theme is a set of these values: Folio (paper and
// ink, as workshop/studies/_kit/folio.css has them) or Lumen (neutral grays
// and glass, workshop/studies/interstellar). Theme, mode and the theme's one
// color come from the selection azure-folio keeps (tools/azure-folio), which
// Settings › Appearance writes; Looks.js derives the color exactly as apps
// and the boot screen get it. Every change glides.
Singleton {
    id: root

    readonly property string selectionPath: Quickshell.env("HOME") + "/.local/state/nixos-config/azure-folio/selection.json"
    // The selection azure-folio saved, with what was just chosen on top
    // (Services/Theming sets `pending` at the click and azure-folio catches up
    // seconds later), so Folio itself changes at once.
    property var saved: ({})
    property var pending: ({})
    readonly property var selection: Object.assign({}, saved, pending)
    // Tests and previews can pin a theme, mode or color without touching the
    // selection (FOLIO_INK takes a name from the theme's set or #rrggbb).
    property string forceTheme: Quickshell.env("INTERSTELLAR_THEME") || ""
    property string forceMode: Quickshell.env("FOLIO_MODE") || ""
    property string forceInk: Quickshell.env("FOLIO_INK") || ""

    FileView {
        path: root.selectionPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.saved = JSON.parse(text()); } catch (e) { console.warn("Theme: unreadable selection", e); return; }
            // What azure-folio has now written is no longer pending.
            const p = {};
            for (const k in root.pending) if (root.saved[k] !== root.pending[k]) p[k] = root.pending[k];
            root.pending = p;
        }
    }

    readonly property string name: { const t = forceTheme || selection.theme || "folio"; return Looks.THEMES.indexOf(t) >= 0 ? t : "folio"; }
    readonly property bool lumen: name === "lumen"
    // Folio's printmaking: plates, develop, halftone, the cross grid. Lumen
    // has none of it; its surfaces fade and its wallpaper is a nebula.
    readonly property bool prints: !lumen
    readonly property string mode: forceMode || selection.mode || "light"
    readonly property bool dark: mode === "dark"

    // A theme's color as picked: a name from its set or #rrggbb.
    function pickOf(theme) {
        if (forceInk && theme === name && Looks.validPick(theme, forceInk)) return forceInk;
        if (theme === "lumen") return selection.accent === "custom" ? (selection.customAccent || "blue") : (selection.accent || "blue");
        return selection.ink === "custom" ? (selection.customInk || "azure") : (selection.ink || "azure");
    }
    readonly property string pick: pickOf(name)
    // Folio's named ink, or "custom".
    readonly property string inkName: Looks.INKS[pickOf("folio")] ? pickOf("folio") : "custom"
    // [color, text on it] in each mode, as Looks.derive gives them.
    readonly property var lightLook: Looks.derive(name, "light", pick)
    readonly property var darkLook: Looks.derive(name, "dark", pick)
    readonly property var look: dark ? darkLook : lightLook
    // Folio's ink in light and dark, for plates and previews pinned to a mode.
    readonly property var inkPair: [Looks.derive("folio", "light", pickOf("folio"))[0], Looks.derive("folio", "dark", pickOf("folio"))[0]]
    // Folio's named inks, for the Appearance swatches.
    readonly property var inks: Looks.INKS

    function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t); }

    // The four sources; everything else derives from them. "ink" is the
    // theme's color in both themes (Lumen's accent), "paper" its window.
    property color paper: lumen ? (dark ? "#141416" : "#ffffff") : (dark ? "#101d33" : "#f7f4e9")
    property color ink: look[0]
    property color text: lumen ? (dark ? "#f5f5f7" : "#1d1d1f") : (dark ? "#e4e9f0" : "#1a2740")
    property color sheetBase: lumen ? (dark ? "#1f1f22" : "#f6f6f8") : (dark ? "#182a49" : "#fffdf6")
    Behavior on paper { ColorAnimation { duration: root.tPage; easing.type: Easing.OutCubic } }
    Behavior on ink { ColorAnimation { duration: root.tPage; easing.type: Easing.OutCubic } }
    Behavior on text { ColorAnimation { duration: root.tPage; easing.type: Easing.OutCubic } }
    Behavior on sheetBase { ColorAnimation { duration: root.tPage; easing.type: Easing.OutCubic } }

    // Higher contrast (Settings › Accessibility): secondary text nearer the
    // text, firmer hairlines, wells and sheets more opaque.
    readonly property bool high: Settings.get("contrast") === "high"
    readonly property color text2: mix(text, paper, high ? 0.16 : 0.34)
    readonly property color text3: mix(text, paper, high ? 0.3 : 0.56)
    // Folio tints wells and hairlines with its ink; Lumen's are neutral.
    readonly property color tint: lumen ? text : ink
    readonly property color wash: mix(paper, tint, lumen ? 0.045 : 0.07)
    readonly property color well: rgba(tint, lumen ? (high ? 0.09 : 0.055) : (high ? 0.13 : 0.09))
    readonly property color wellStrong: rgba(tint, lumen ? (high ? 0.16 : 0.1) : (high ? 0.24 : 0.16))
    readonly property color rule: rgba(tint, lumen ? (high ? 0.32 : 0.11) : (high ? 0.42 : 0.16))
    readonly property color ruleStrong: rgba(tint, lumen ? (high ? 0.5 : 0.2) : (high ? 0.62 : 0.30))
    // Text and icons on an ink fill: Folio's paper, or white or near-black on
    // Lumen's accent, whichever reads. (Not "onInk": QML reads on+Capital as a handler.)
    readonly property color inkText: look[1]
    readonly property color sheet: rgba(sheetBase, high ? 0.95 : 0.74)
    readonly property color sheetStrong: rgba(sheetBase, 0.93)
    readonly property color highlight: dark ? Qt.rgba(1, 1, 1, lumen ? 0.06 : 0.07) : Qt.rgba(1, 1, 1, 0.6)
    readonly property color shade: lumen ? "#000000" : dark ? "#02060e" : "#101d33"
    // The island and the dock's dark tiles: deep ink in both modes (Lumen: black).
    readonly property color island: lumen ? "#000000" : mix(Qt.color("#0b1424"), Qt.color(inkPair[0]), 0.46)
    readonly property color islandText: lumen ? "#f5f5f7" : "#eef2f8"
    readonly property color islandInk: lumen ? darkLook[0] : inkPair[1]
    // Reds that read on the island: the recording dot, alert text.
    readonly property color islandAlert: lumen ? "#ff453a" : "#f07b70"
    readonly property color islandAlertText: lumen ? "#ff6961" : "#f4a49a"
    readonly property color success: lumen ? (dark ? "#30d158" : "#248a3d") : dark ? "#8cc5a3" : mix(Qt.color("#3f7d5c"), ink, 0.2)
    readonly property color warning: lumen ? (dark ? "#ff9f0a" : "#b25000") : dark ? "#e3b267" : "#b07a26"
    readonly property color error: lumen ? (dark ? "#ff453a" : "#d70015") : dark ? "#f09088" : "#b4473f"

    // Shape. Radii nest: an inner corner is the outer one minus the padding
    // between them, so curves stay concentric (inner()).
    readonly property real rXs: lumen ? 5 : 6
    readonly property real rS: lumen ? 8 : 10
    readonly property real rM: lumen ? 11 : 14
    readonly property real rL: lumen ? 16 : 20
    readonly property real rXl: lumen ? 22 : 28
    readonly property real rWindow: 12          // windows, as niri clips them (the look's 12 px)
    function inner(outer, pad) { return Math.max(4, outer - pad); }

    // Type
    readonly property string ui: "Inter"
    readonly property string mono: "IBM Plex Mono"
    // The big type (clocks, titles): Folio's blackletter, Lumen's Inter Display.
    readonly property string hero: lumen ? "Inter Display" : "Jacquard 24"
    readonly property int heroWeight: lumen ? Font.DemiBold : Font.Normal
    // Captions (Cap): Folio's mono capitals, Lumen's small sentence case.
    readonly property string capFamily: lumen ? ui : mono
    readonly property int capCase: lumen ? Font.MixedCase : Font.AllUppercase
    readonly property real capSpacing: lumen ? 0 : 1.2
    readonly property int capWeight: lumen ? Font.DemiBold : Font.Medium
    // Text size (Settings › Accessibility) scales every type token.
    readonly property real textScale: Math.max(0.9, Math.min(1.6, +Settings.get("text.scale") || 1))
    readonly property real fsCap: (lumen ? 11.5 : 10.5) * textScale
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
