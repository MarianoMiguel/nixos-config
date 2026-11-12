import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// The page's head: the date in caps, the time printed large in ink (a new
// minute prints in dot by dot while the page is open), the weather, and the
// plate's number and title like a book plate's caption.
Item {
    id: root
    required property var feed
    property bool printing: false       // open and settled: new minutes print

    readonly property date now: new Date(feed.now)
    readonly property string dateText: now.toLocaleDateString(Qt.locale("es_AR"), "dddd, d 'de' MMMM")
    readonly property var plate: Art.plate(Art.current)
    readonly property int plateIndex: Art.plates.findIndex(p => p.id === Art.current)

    function roman(n) {
        const r = [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]];
        let s = "";
        for (const [v, c] of r) while (n >= v) { s += c; n -= v; }
        return s;
    }

    implicitHeight: col.implicitHeight + 8

    // Four times the face's 24-unit pixel grid: whole pixels, crisp.
    component ClockFace: Text {
        height: 72
        verticalAlignment: Text.AlignVCenter
        color: Theme.ink
        font.family: Theme.hero; font.weight: Theme.heroWeight
        font.pixelSize: 96
        font.hintingPreference: Font.PreferFullHinting
        renderType: Text.NativeRendering
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 6; rightMargin: 6; topMargin: 6 }
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Cap { text: root.dateText; Layout.fillWidth: true; Layout.minimumWidth: 0 }
            Cap { text: root.plateIndex >= 0 ? "Pl. " + root.roman(root.plateIndex + 1) : ""; visible: text !== "" && Theme.prints }
        }
        // Widgets/PrintText, with native rendering so the pixel face stays crisp.
        Item {
            id: clock
            readonly property string text: Qt.formatTime(root.now, "HH:mm")
            property string shown: text
            property string old: ""
            onTextChanged: {
                if (!root.printing || Settings.motion < 0.1) { shown = text; return; }
                old = shown;
                shown = text;
                incoming.run(0, 1, 600);
            }
            Layout.leftMargin: -2
            Layout.topMargin: 6
            Layout.bottomMargin: 8
            Layout.preferredHeight: 72
            Layout.preferredWidth: face.implicitWidth

            Develop {
                anchors.fill: parent
                visible: incoming.running
                invert: true
                progress: incoming.progress
                seed: incoming.seed
                ClockFace { text: clock.old }
            }
            Develop {
                id: incoming
                anchors.fill: parent
                ClockFace { id: face; text: clock.shown }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Label { text: root.feed.weather; color: Theme.text2; font.pixelSize: Theme.fsS; Layout.fillWidth: true; Layout.minimumWidth: 0 }
            Cap { text: root.plate ? root.plate.title : ""; visible: text !== "" && Theme.prints; Layout.maximumWidth: 150 }
        }
    }
}
