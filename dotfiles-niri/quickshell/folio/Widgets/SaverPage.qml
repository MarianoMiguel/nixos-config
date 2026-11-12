import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// The screensaver in the lock's split: the theme's art on the left (Folio's
// plate breathing, Lumen's sky), the page on the right with the date, the
// clock and a few quiet lines (the weather, what is playing). Other screens
// show the art alone. It shares the lock's proportions, so the saver hands
// over to the lock without a seam. Against burn-in the page's content moves
// to a new resting place every two minutes, with a short glide; between
// moves nothing on the page redraws.
Item {
    id: root
    property string plate: Art.current
    property bool main: true
    property bool running: true             // the saver is up: drift and breathe
    property string caption: ""             // a fixture's credit in place of the plate's
    property int textureWidth: 0            // the art's source width (0: full), for previews
    readonly property real share: 0.56      // as LockPage

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property var esAR: Qt.locale("es_AR")

    // The art.
    Plate {
        id: art
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
        width: root.main ? root.width * root.share : root.width
        portrait: root.main
        plate: root.plate
        breathe: root.running ? 1 : 0
        lift: 0.06
        developOnLoad: false
        textureWidth: root.textureWidth
    }

    // The plate's credit, bottom left of the art (Folio; Lumen's sky is its own).
    Item {
        readonly property string text: {
            if (root.caption) return root.caption;
            const p = Art.plate(art.plate);
            const c = Art.collections.find(x => x.art.some(a => a.id === art.plate));
            return p ? (c ? c.name + " · " : "") + p.title : "";
        }
        visible: text !== "" && Theme.prints
        x: 20
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        width: Math.min(credit.implicitWidth + 22, art.width - 40)
        height: credit.implicitHeight + 14
        Frost { anchors.fill: parent; source: art; radius: Theme.rS }
        Sheet { anchors.fill: parent; radius: Theme.rS; color: Theme.sheetStrong }
        Cap {
            id: credit
            anchors.fill: parent
            anchors.leftMargin: 11; anchors.rightMargin: 11
            verticalAlignment: Text.AlignVCenter
            color: Theme.text2
            text: parent.text
        }
    }

    // The page.
    Item {
        id: page
        visible: root.main
        x: art.width
        width: root.width - art.width
        height: root.height
        readonly property real pad: Math.max(28, Math.min(72, root.width * 0.045))

        RectangularShadow {
            anchors.fill: parent
            offset: Qt.vector2d(-30, 0)
            blur: 60
            color: Theme.rgba(Theme.shade, 0.12)
        }
        Rectangle { anchors.fill: parent; color: Theme.paper }
        Rectangle { x: -1; width: 1; height: parent.height; color: Theme.rule }

        // The tab: Interstellar's mark. Folio hangs it in ink from the top
        // edge, as the lock's name tab; Lumen sets a quiet pill below it.
        Rectangle {
            id: tab
            anchors.horizontalCenter: parent.horizontalCenter
            y: Theme.lumen ? 26 : 0
            width: tabRow.implicitWidth + (Theme.lumen ? 32 : 44)
            height: Theme.lumen ? 34 : 39
            color: Theme.lumen ? Theme.wellStrong : Theme.ink
            topLeftRadius: Theme.lumen ? height / 2 : 0
            topRightRadius: Theme.lumen ? height / 2 : 0
            bottomLeftRadius: Theme.lumen ? height / 2 : Theme.rM
            bottomRightRadius: Theme.lumen ? height / 2 : Theme.rM
            Row {
                id: tabRow
                x: Theme.lumen ? 16 : 22
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9
                Mark { width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter; color: Theme.lumen ? Theme.text : Theme.inkText }
                Label { text: "Interstellar"; color: Theme.lumen ? Theme.text : Theme.inkText; font.pixelSize: 15; font.weight: Font.Medium }
            }
        }

        // Date, clock, a rule and the quiet lines, centred between tab and foot.
        Column {
            id: center
            x: page.pad + root.dx
            y: tab.y + tab.height + Math.max(20, (foot.y - tab.y - tab.height - height) / 2) + root.dy
            width: page.width - 2 * page.pad
            readonly property real gap: Math.max(22, Math.min(40, root.height * 0.04))

            Cap { width: parent.width; text: root.esAR.toString(clock.date, "dddd, d 'de' MMMM") }
            Item { width: 1; height: 6 }
            // A line box of 0.78 em with the figures centred, as the lock's clock.
            Item {
                id: clockBox
                readonly property real size: Math.max(110, Math.min(200, root.width * 0.13))
                width: clockText.implicitWidth
                height: size * 0.78
                PrintText {
                    id: clockText
                    x: -6
                    y: (clockBox.height - implicitHeight) / 2
                    text: Qt.formatTime(clock.date, "HH:mm")
                    color: Theme.lumen ? Theme.text : Theme.ink
                    font.family: Theme.hero; font.weight: Theme.heroWeight
                    font.pixelSize: clockBox.size
                    font.features: { "tnum": 1 }
                }
            }
            Item { width: 1; height: center.gap }
            Rectangle { width: parent.width; height: 1; color: Theme.ruleStrong }
            Item { width: 1; height: center.gap }
            Column {
                width: parent.width
                spacing: 12
                Repeater {
                    model: root.lines
                    Row {
                        required property var modelData
                        spacing: 10
                        Icon { name: modelData.icon; size: 20; color: Theme.ink; anchors.verticalCenter: parent.verticalCenter }
                        Label { text: modelData.text; color: Theme.text2; width: Math.min(implicitWidth, center.width - 30) }
                    }
                }
            }
        }

        // The status and how to come back.
        Item {
            id: foot
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: page.pad; rightMargin: page.pad }
            height: 56
            Rectangle { width: parent.width; height: 1; color: Theme.rule }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16
                Repeater {
                    model: [
                        { "icon": "wifi", "text": Network.wired ? "Wired" : Network.ssid },
                        { "icon": "battery", "text": Battery.present ? Battery.percent + "%" : "" }
                    ].filter(s => s.text)
                    Row {
                        required property var modelData
                        spacing: 6
                        Icon { name: modelData.icon; size: 14; color: Theme.text3; anchors.verticalCenter: parent.verticalCenter }
                        Cap { text: modelData.text; width: Math.min(implicitWidth, 220); anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
            Cap { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: "Touch anything to return" }
        }
    }

    // The quiet lines: the weather and what is playing, when there is any.
    readonly property var lines: {
        const out = [];
        if (Weather.summary) out.push({ "icon": Weather.isDay ? "sun" : "moon", "text": Weather.summary });
        if (Media.active && Media.title) out.push({ "icon": "music", "text": Media.title + (Media.artist ? " · " + Media.artist : "") });
        return out;
    }

    // Burn-in: four resting places, a short glide every two minutes.
    property real dx: 0
    property real dy: 0
    Behavior on dx { NumberAnimation { duration: Math.max(1, 1600 * Theme.motion); easing.type: Easing.InOutCubic } }
    Behavior on dy { NumberAnimation { duration: Math.max(1, 1600 * Theme.motion); easing.type: Easing.InOutCubic } }
    property int place: 0
    readonly property var places: [[0, 0], [14, -0.035], [-10, 0.03], [8, 0.015]]
    Timer {
        interval: 120000; repeat: true
        running: root.running && root.main
        onTriggered: {
            root.place = (root.place + 1) % root.places.length;
            root.dx = root.places[root.place][0];
            root.dy = root.places[root.place][1] * root.height;
        }
    }
    onRunningChanged: if (!running) { place = 0; dx = 0; dy = 0; }
}
