import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import "../../Common/Sun.js" as Sun
import "../../Common/Looks.js" as Looks

// Appearance: how the whole desktop looks (the Appearance and Interstellar
// studies). Theme, mode, color and plate go through azure-folio, which
// re-themes apps with themeport and the login and boot screens through their
// bridges; everything else is the shell's Settings. "Sunset" mode follows the
// sun at Settings' weather place (SystemSettings runs it whether this page is open or not).
SettingsPage {
    id: page
    title: "Appearance"
    description: Theming.busy
        ? "Applying " + Theming.label + " to your apps: GTK, Qt, Chrome and the terminal follow in a moment, the disk-unlock screen from the next boot."
        : "How the whole desktop looks, in one place. Every change applies at once."

    // The desktop changes at the click; apps follow when azure-folio is done.
    function setMode(m) {
        Settings.set("mode.auto", m === "sunset");
        if (m !== "sunset" && m !== Theme.mode) Theming.set({ "mode": m }, m + " mode");
    }
    readonly property var place: Settings.get("weather.place") || ["Campana", -34.16, -58.96]
    readonly property string sunLine: {
        const t = Sun.times(new Date(), place[1], place[2]);
        if (!t) return "";
        const f = d => d.toLocaleTimeString(Qt.locale("es_AR"), "HH:mm");
        return "Dark from " + f(t.sunset) + " to " + f(t.sunrise) + " in " + place[0] + ".";
    }

    Item { Layout.preferredHeight: 10 }
    Rectangle {
        Layout.fillWidth: true; Layout.preferredHeight: width / 1.7; radius: 16; clip: true; color: Theme.wash
        border.color: Theme.rule
        MiniDesktop { anchors.fill: parent; anchors.margins: 1; breathe: Settings.get("plates.breathe") }
        Rectangle { x: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 12; width: tag.implicitWidth + 20; height: 26; radius: 9; color: Theme.sheetStrong; border.color: Theme.rule
            Cap { id: tag; anchors.centerIn: parent; text: { if (Theme.lumen) return "Lumen · " + (Theme.pick.charAt(0) === "#" ? "your color" : Theme.pick); const p = Art.plate(Art.current); return p ? p.collectionName + " · " + p.title : ""; } } }
    }

    // Theme
    Label { text: "Theme"; font.weight: Font.DemiBold; font.pixelSize: 15; Layout.topMargin: 28; Component.onCompleted: page.mark("theme", this) }
    Label { text: "Everything Interstellar draws, from the bar to the disk-unlock screen."; color: Theme.text2; font.pixelSize: Theme.fsS; Layout.fillWidth: true; Layout.bottomMargin: 10 }
    RowLayout {
        Layout.fillWidth: true; spacing: 10
        Repeater {
            model: [{ "id": "folio", "t": "Folio", "s": "Ink on paper, printed plates" }, { "id": "lumen", "t": "Lumen", "s": "Graphite and glass" }]
            OptionCard {
                id: tcard
                required property var modelData
                title: modelData.t; subtitle: modelData.s
                previewRatio: 16 / 8
                selected: Theme.name === modelData.id
                busy: selected && Theming.busy && "theme" in Theme.pending
                onChosen: if (!selected) Theming.set({ "theme": modelData.id }, modelData.t)
                Plate { anchors.fill: parent; forceTheme: tcard.modelData.id; plate: Art.current; textureWidth: 960; developOnLoad: false }
                // A specimen of the theme's type and color on its own window.
                Rectangle {
                    readonly property bool lumen: tcard.modelData.id === "lumen"
                    readonly property string bg: Looks.BACKGROUND[tcard.modelData.id][Theme.mode]
                    anchors { left: parent.left; bottom: parent.bottom; margins: 10 }
                    width: spec.implicitWidth + 24; height: 44; radius: lumen ? 10 : 12
                    color: bg
                    Text {
                        id: spec
                        anchors.centerIn: parent
                        text: "Aa"
                        font.family: parent.lumen ? "Inter Display" : "Jacquard 24"
                        font.weight: parent.lumen ? Font.DemiBold : Font.Normal
                        font.pixelSize: parent.lumen ? 26 : 32
                        color: Looks.derive(tcard.modelData.id, Theme.mode, Theme.pickOf(tcard.modelData.id))[0]
                    }
                }
            }
        }
    }

    // Mode
    Label { text: "Mode"; font.weight: Font.DemiBold; font.pixelSize: 15; Layout.topMargin: 28 }
    Label { text: page.sunLine ? "Sunset follows the sun. " + page.sunLine : "Light, dark, or following the sun."; color: Theme.text2; font.pixelSize: Theme.fsS; Layout.fillWidth: true; Layout.bottomMargin: 10 }
    RowLayout {
        Layout.fillWidth: true; spacing: 10
        Repeater {
            model: [{ "id": "light", "t": "Light", "s": Theme.lumen ? "White and glass" : "Ink on paper" }, { "id": "dark", "t": "Dark", "s": Theme.lumen ? "Graphite under the stars" : "Moonlit plates on night" }, { "id": "sunset", "t": "Sunset", "s": "Light by day, dark at night" }]
            OptionCard {
                required property var modelData
                title: modelData.t; subtitle: modelData.s
                selected: modelData.id === "sunset" ? Settings.get("mode.auto") === true : (Settings.get("mode.auto") !== true && Theme.mode === modelData.id)
                busy: selected && Theming.busy && "mode" in Theme.pending
                onChosen: page.setMode(modelData.id)
                Plate { anchors.fill: parent; plate: Art.current; forceMode: modelData.id === "sunset" ? "light" : modelData.id; textureWidth: 960; developOnLoad: false }
                // Sunset: the right half of the same plate at night.
                Item {
                    visible: modelData.id === "sunset"
                    x: parent.width * 0.5; width: parent.width * 0.5; height: parent.height; clip: true
                    Plate { x: -parent.x; width: parent.parent.width; height: parent.height; plate: Art.current; forceMode: "dark"; textureWidth: 960; developOnLoad: false }
                }
            }
        }
    }

    // Color: Folio's ink or Lumen's accent. Any color works; Looks keeps it readable.
    Label { text: Theme.lumen ? "Color" : "Ink"; font.weight: Font.DemiBold; font.pixelSize: 15; Layout.topMargin: 28; Component.onCompleted: page.mark("color", this) }
    Label {
        text: (Theme.lumen ? "One color for controls, the island and the sky; apps and the unlock screen take it too."
                           : "One ink for everything: art, controls, Chrome, the terminal.") + " Any color works: it is kept readable."
        color: Theme.text2; font.pixelSize: Theme.fsS; Layout.fillWidth: true; Layout.bottomMargin: 10; wrapMode: Text.WordWrap; maximumLineCount: 2
    }
    readonly property string colorKey: Theme.lumen ? "accent" : "ink"
    readonly property string customColor: (Theme.lumen ? Theme.selection.customAccent : Theme.selection.customInk) || ""
    readonly property bool customChosen: (Theme.lumen ? Theme.selection.accent : Theme.selection.ink) === "custom"
    function choose(name, label) { const p = {}; p[colorKey] = name; Theming.set(p, label); }
    RowLayout {
        visible: !Theme.lumen
        Layout.fillWidth: true; spacing: 10
        Repeater {
            model: ["azure", "cobalt", "slate", "custom"]
            OptionCard {
                id: icard
                required property string modelData
                readonly property var pair: modelData === "custom" ? [Looks.derive("folio", "light", page.customColor || "#5a7cf0")[0], Looks.derive("folio", "dark", page.customColor || "#5a7cf0")[0]] : Theme.inks[modelData]
                title: modelData === "custom" ? "Any ink" : modelData.charAt(0).toUpperCase() + modelData.slice(1)
                previewRatio: 16 / 7
                selected: Theme.inkName === modelData
                busy: selected && Theming.busy && "ink" in Theme.pending
                onChosen: if (Theme.inkName !== modelData) page.choose(modelData === "custom" ? (page.customColor || "#5a7cf0") : modelData, title)
                Row {
                    anchors.fill: parent
                    Rectangle { width: parent.width / 2; height: parent.height; color: icard.pair[0]
                        Cap { anchors { left: parent.left; bottom: parent.bottom; margins: 8 } text: icard.pair[0]; color: "#f7f4e9" } }
                    Rectangle { width: parent.width / 2; height: parent.height; color: "#101d33"
                        Cap { anchors { left: parent.left; bottom: parent.bottom; margins: 8 } text: icard.pair[1]; color: icard.pair[1] } }
                }
            }
        }
    }
    Flow {
        visible: Theme.lumen
        Layout.fillWidth: true; spacing: 10
        Repeater {
            model: Object.keys(Looks.ACCENTS).concat(["custom"])
            Item {
                id: sw
                required property string modelData
                readonly property bool custom: modelData === "custom"
                readonly property bool chosen: custom ? page.customChosen : (Theme.selection.accent || "blue") === modelData && !page.customChosen
                readonly property color shown: custom ? (page.customColor ? Looks.derive("lumen", Theme.mode, page.customColor)[0] : "transparent") : Looks.derive("lumen", Theme.mode, modelData)[0]
                width: 40; height: 40
                activeFocusOnTab: true
                Keys.onPressed: event => KeyNav.press(event, () => area.clicked(null))
                FocusRing { radius: 20 }
                Rectangle {
                    anchors.centerIn: parent; width: 40; height: 40; radius: 20; color: "transparent"
                    border.width: 2; border.color: sw.chosen ? (sw.custom && !page.customColor ? Theme.text : sw.shown) : "transparent"
                }
                // The custom swatch is a color wheel until a color is picked.
                Rectangle {
                    anchors.centerIn: parent; width: 30; height: 30; radius: 15
                    color: sw.shown; border.width: 1; border.color: Theme.rule
                    visible: !sw.custom || page.customColor !== ""
                }
                Rectangle {
                    anchors.centerIn: parent; width: 30; height: 30; radius: 15; visible: sw.custom && page.customColor === ""
                    gradient: Gradient { orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#f2453a" } GradientStop { position: 0.25; color: "#ffc800" } GradientStop { position: 0.5; color: "#30c35a" }
                        GradientStop { position: 0.75; color: "#0a7aff" } GradientStop { position: 1; color: "#a050e8" } }
                }
                Icon { anchors.centerIn: parent; visible: sw.chosen; name: "check"; size: 14; stroke: 2.6; color: sw.custom && !page.customColor ? Theme.text : Looks.derive("lumen", Theme.mode, sw.custom ? page.customColor : sw.modelData)[1] }
                MouseArea {
                    id: area
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: if (!sw.chosen) page.choose(sw.custom ? (page.customColor || "#5a7cf0") : sw.modelData, sw.custom ? "your color" : sw.modelData)
                }
            }
        }
    }
    // Any color: shown while dragging, applied when let go.
    ColorPick {
        visible: page.customChosen
        Layout.fillWidth: true; Layout.topMargin: 12
        theme: Theme.name
        value: page.customColor
        onMoved: hex => { const p = {}; p[page.colorKey] = hex; Theming.preview(p); }
        onChosen: hex => page.choose(hex, "your color")
    }

    // Wallpaper
    Label { text: "Wallpaper"; font.weight: Font.DemiBold; font.pixelSize: 15; Layout.topMargin: 32; Component.onCompleted: page.mark("wallpaper", this) }
    Label {
        text: Theme.lumen ? "Lumen draws its sky from your color: soft light by day, stars at night, on every screen and behind the lock."
                          : "A collection is a theme bundle: its plates and its lock art. Plates print in the current ink."
        color: Theme.text2; font.pixelSize: Theme.fsS; Layout.fillWidth: true; Layout.bottomMargin: 10; wrapMode: Text.WordWrap; maximumLineCount: 2
    }
    GridLayout {
        visible: !Theme.lumen
        Layout.fillWidth: true; columns: 4; columnSpacing: 10; rowSpacing: 10
        Repeater {
            model: Art.collections
            OptionCard {
                required property var modelData
                title: modelData.name; subtitle: modelData.description
                previewRatio: 16 / 9
                selected: Theme.selection.collection === modelData.id
                busy: selected && Theming.busy && "collection" in Theme.pending
                onChosen: if (!selected) Theming.set({ "collection": modelData.id, "art": 0 }, modelData.name)
                Row {
                    anchors.fill: parent; spacing: 4
                    Repeater { model: modelData.art.slice(0, 2)
                        Plate { required property var modelData; width: (parent.width - 4) / 2; height: parent.height; plate: modelData.id; textureWidth: 640; zoom: 1.6; developOnLoad: false } }
                }
            }
        }
    }
    RowLayout {
        visible: !Theme.lumen
        Layout.fillWidth: true; Layout.topMargin: 10; spacing: 10
        Repeater {
            model: (Art.collections.find(c => c.id === Theme.selection.collection) || { "art": [] }).art
            OptionCard {
                required property var modelData
                required property int index
                title: modelData.title; subtitle: modelData.credit
                selected: (Theme.selection.art || 0) === index
                busy: selected && Theming.busy && "art" in Theme.pending
                onChosen: if (!selected) Theming.set({ "art": index }, "“" + modelData.title + "”")
                Plate { anchors.fill: parent; plate: modelData.id; textureWidth: 1280; developOnLoad: false }
            }
        }
    }
    Rectangle {
        visible: !Theme.lumen
        Layout.fillWidth: true; Layout.topMargin: 12; radius: Theme.rM; color: Theme.well; border.color: Theme.rule
        implicitHeight: wpRows.implicitHeight
        ColumnLayout {
            id: wpRows; width: parent.width; spacing: 0
            SettingRow { icon: "sparkle"; label: "Moving dither"; hint: "The plate keeps re-printing itself. Plugged in: it holds still on battery, which also spares the blur behind panels."
                Choice {
                    options: [{ "value": "always", "label": "Always" }, { "value": "plugged", "label": "Plugged in" }, { "value": "off", "label": "Off" }]
                    value: !(Settings.get("plates.breathe") > 0) ? "off" : Settings.get("plates.breatheOnBattery") === true ? "always" : "plugged"
                    onChosen: v => { Settings.set("plates.breathe", v === "off" ? 0 : 1); Settings.set("plates.breatheOnBattery", v === "always"); }
                } }
            SettingRow { icon: "moon"; label: "Plates in dark mode"; hint: "Moonlit keeps the picture's tones; Negative prints it light on night."
                Choice { options: [{ "value": "moonlit", "label": "Moonlit" }, { "value": "negative", "label": "Negative" }]; value: Settings.get("plates.dark"); onChosen: v => Settings.set("plates.dark", v) } }
        }
    }

    // Motion
    Label { text: "Motion"; font.weight: Font.DemiBold; font.pixelSize: 15; Layout.topMargin: 32; Component.onCompleted: page.mark("motion", this) }
    Label { text: "How much the desktop moves."; color: Theme.text2; font.pixelSize: Theme.fsS; Layout.fillWidth: true; Layout.bottomMargin: 10 }
    RowLayout {
        Layout.fillWidth: true; spacing: 10
        Repeater {
            model: [{ "id": "full", "t": "Full", "s": Theme.lumen ? "Springs, fades and glides" : "Develop, bleed, leaf, stamp", "ms": 520 }, { "id": "gentle", "t": "Gentle", "s": "Half the time, half the travel", "ms": 260 }, { "id": "still", "t": "Still", "s": "Changes cut; plates appear whole", "ms": 1 }]
            OptionCard {
                id: mcard
                required property var modelData
                title: modelData.t; subtitle: modelData.s
                selected: Settings.get("motion") === modelData.id
                onChosen: Settings.set("motion", modelData.id)
                Rectangle { anchors.fill: parent; color: Theme.wash
                    Rectangle { x: parent.width * 0.06; y: parent.height * 0.14; width: parent.width * 0.38; height: parent.height * 0.56; radius: 10; color: Theme.sheetBase; border.color: Theme.rule }
                    Rectangle {
                        id: demo
                        y: parent.height * 0.1; height: parent.height * 0.8; width: parent.width * 0.46
                        x: parent.width * 0.5; radius: 14; color: Theme.sheetStrong; border.color: Theme.rule
                        transform: Rotation { id: rot; origin.x: demo.width; origin.y: demo.height / 2; axis { x: 0; y: 1; z: 0 } angle: 0 }
                        Column { anchors.fill: parent; anchors.margins: 10; spacing: 6
                            Rectangle { width: parent.width * 0.6; height: 8; radius: 4; color: Theme.ink }
                            Repeater { model: 2; Rectangle { width: parent.width; height: 8; radius: 4; color: Theme.wellStrong } } }
                    }
                    HoverHandler { onHoveredChanged: if (hovered) play.restart() }
                    SequentialAnimation {
                        id: play
                        ParallelAnimation {
                            NumberAnimation { target: rot; property: "angle"; from: -18; to: 0; duration: mcard.modelData.ms; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }
                            NumberAnimation { target: demo; property: "opacity"; from: 0; to: 1; duration: mcard.modelData.ms }
                        }
                    }
                }
            }
        }
    }

    // Lock & screensaver
    Label { text: "Lock & screensaver"; font.weight: Font.DemiBold; font.pixelSize: 15; Layout.topMargin: 32; Component.onCompleted: page.mark("lock", this) }
    Label { text: "The screensaver is the lock's split: the " + (Theme.lumen ? "sky" : "plate, breathing,") + " beside a page with the date, the clock, the weather and what's playing. Touch anything and it lifts away."; color: Theme.text2; font.pixelSize: Theme.fsS; Layout.fillWidth: true; Layout.bottomMargin: 10; wrapMode: Text.WordWrap; maximumLineCount: 2 }
    // The screensaver itself (Widgets/SaverPage), laid out for a 1920 x 1200
    // screen and scaled into the card.
    Rectangle {
        id: saverCard
        Layout.fillWidth: true; Layout.preferredHeight: width / 1.6; radius: 14; clip: true; color: Theme.paper; border.color: Theme.rule
        SaverPage {
            width: 1920; height: 1200
            transform: Scale { xScale: (saverCard.width - 2) / 1920; yScale: (saverCard.height - 2) / 1200 }
            x: 1; y: 1
            textureWidth: 1600
        }
    }
    Rectangle {
        Layout.fillWidth: true; Layout.topMargin: 12; radius: Theme.rM; color: Theme.well; border.color: Theme.rule
        implicitHeight: lockRows.implicitHeight
        ColumnLayout {
            id: lockRows; width: parent.width; spacing: 0
            SettingRow { icon: "sparkle"; label: "Start the screensaver after"
                Choice { options: [{ "value": 0, "label": "Never" }, { "value": 120, "label": "2 min" }, { "value": 300, "label": "5 min" }, { "value": 600, "label": "10 min" }]; value: Settings.get("screensaver.after"); onChosen: v => Settings.set("screensaver.after", v) } }
            SettingRow { icon: "battery"; label: "Lock on battery after"
                Choice { options: [{ "value": 120, "label": "2 min" }, { "value": 300, "label": "5 min" }, { "value": 600, "label": "10 min" }]; value: Settings.get("idle.lockBattery"); onChosen: v => Settings.set("idle.lockBattery", v) } }
            SettingRow { icon: "bolt"; label: "Lock when plugged in after"
                Choice { options: [{ "value": 300, "label": "5 min" }, { "value": 600, "label": "10 min" }, { "value": 1800, "label": "30 min" }]; value: Settings.get("idle.lockAC"); onChosen: v => Settings.set("idle.lockAC", v) } }
            SettingRow { icon: "moon"; label: "Hibernate on battery after"; hint: "The lock screen goes up first."
                Choice { options: [{ "value": 900, "label": "15 min" }, { "value": 1800, "label": "30 min" }, { "value": 0, "label": "Never" }]; value: Settings.get("idle.hibernateBattery"); onChosen: v => Settings.set("idle.hibernateBattery", v) } }
        }
    }

    // Desktop & dock
    Label { text: "Desktop & dock"; font.weight: Font.DemiBold; font.pixelSize: 15; Layout.topMargin: 32; Component.onCompleted: page.mark("desktop", this) }
    Label { text: "The island, the sidebar and the dock."; color: Theme.text2; font.pixelSize: Theme.fsS; Layout.fillWidth: true; Layout.bottomMargin: 10 }
    Rectangle {
        Layout.fillWidth: true; radius: Theme.rM; color: Theme.well; border.color: Theme.rule
        implicitHeight: deskRows.implicitHeight
        ColumnLayout {
            id: deskRows; width: parent.width; spacing: 0
            SettingRow { icon: "grid"; label: "Magnify the dock"
                Toggle { checked: Settings.get("dock.magnify"); onToggled: v => Settings.set("dock.magnify", v) } }
            SettingRow { icon: "display"; label: "Keep windows clear of the dock"; hint: "Windows stop above it, as on a Mac. Off, they reach the bottom edge and the dock floats over them."
                Toggle { checked: Settings.get("dock.reserve") !== false; onToggled: v => Settings.set("dock.reserve", v) } }
            SettingRow { icon: "image"; label: "App icons"; hint: "As shipped, on paper plates when not square, or printed in the ink."
                Choice { options: [{ "value": "original", "label": "Original" }, { "value": "plated", "label": "Plated" }, { "value": "printed", "label": "Printed" }]; value: Settings.get("dock.icons"); onChosen: v => Settings.set("dock.icons", v) } }
            SettingRow { icon: "sidebar"; label: "Sidebar opens from"
                Choice { options: [{ "value": "left", "label": "Left" }, { "value": "right", "label": "Right" }]; value: Settings.get("sidebar.side"); onChosen: v => Settings.set("sidebar.side", v) } }
            SettingRow { icon: "music"; label: "Live activities in the island"; hint: "Music, focus and recording rest there; volume and brightness always show."
                Toggle { checked: Settings.get("island.live"); onToggled: v => Settings.set("island.live", v) } }
            SettingRow { icon: "sparkle"; label: "Play the login"; hint: "Plate, bar, dock and windows arrive in sequence."
                Toggle { checked: Settings.get("login.score"); onToggled: v => Settings.set("login.score", v) } }
        }
    }
}
