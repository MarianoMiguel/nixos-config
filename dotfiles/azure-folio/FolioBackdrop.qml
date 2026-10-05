import QtQuick
import Quickshell
import Quickshell.Io

Rectangle {
    id: folio
    property string userLabel: "MARIANO"
    readonly property bool compact: width < 800 || width < height
    readonly property real split: compact ? 0.36 : 0.5
    readonly property real contentX: width * (split + 0.06)
    readonly property real contentWidth: width * (0.94 - split - 0.06)
    readonly property real authY: height * 0.78
    readonly property color ink: state.inkColor || "#214c94"
    readonly property color paper: state.paper || "#f7f4e9"
    readonly property color muted: state.muted || "#64728a"
    property var state: ({images:[{portrait:"@folioData@/art/dore-nightfall/azure-light-portrait.png", title:"Nightfall",credit:"Gustave Doré · 1866"}],collectionName:"Doré",ink:"azure",mode:"light",art:0,randomLogin:true})
    property int artIndex: 0
    property bool chosen: false
    readonly property var art: state.images?.[artIndex] || state.images?.[0] || ({})
    color: paper

    function newVisit() {
        const count = state.images?.length || 1;
        artIndex = state.randomLogin ? Math.floor(Math.random() * count) : Math.min(state.art || 0, count - 1);
        chosen = true;
    }

    FileView {
        path: Quickshell.env("AZURE_FOLIO_STATE") || "/var/lib/azure-folio/appearance.json"
        watchChanges: true
        blockLoading: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const next = JSON.parse(text());
                if (!Array.isArray(next.images) || !next.images.length) return;
                const collectionChanged = folio.state.collection !== next.collection;
                folio.state = next;
                if (!folio.chosen || collectionChanged) folio.newVisit();
            } catch (error) { console.warn("Azure Folio appearance could not be read:", error); }
        }
    }

    Item {
        width: folio.width * folio.split
        height: folio.height
        clip: true
        Image {
            anchors.fill: parent
            source: "file://" + (folio.art.portrait || "")
            fillMode: Image.PreserveAspectCrop
            asynchronous: false
            smooth: false
        }
        Rectangle { anchors.right: parent.right; height: parent.height; width: 1; color: folio.state.line || "#cbd1d7" }
        Rectangle {
            x: parent.width * 0.04; width: parent.width * 0.92
            y: parent.height * 0.936; height: Math.max(24,folio.height*.035)
            color: folio.paper
            Text {
                anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                text: folio.art.title || "Azure Folio"; color: folio.ink
                font.family: "IBM Plex Mono"; font.pixelSize: Math.max(9,Math.min(13,folio.width*.007))
                elide: Text.ElideRight; width: parent.width * .47
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                text: folio.art.credit || ""; color: folio.ink
                visible: !folio.compact
                font.family: "IBM Plex Mono"; font.pixelSize: Math.max(9,Math.min(12,folio.width*.0065))
            }
        }
    }

    Row {
        x: folio.contentX; y: folio.height*.10; spacing: Math.max(14,folio.width*.012)
        Text { text: "b."; color: folio.ink; font.family: "Jacquard 24"; font.pixelSize: folio.width*.042 }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "@hostname@".toUpperCase(); color: folio.ink
            font.family: "IBM Plex Mono"; font.pixelSize: Math.max(12,folio.width*.010); font.letterSpacing: 2
        }
    }
    SystemClock { id: clock; precision: SystemClock.Minutes }
    Column {
        x: folio.contentX; y: folio.height*.31; width: folio.contentWidth
        spacing: folio.height*.012
        Text {
            text: Qt.formatDateTime(clock.date,"hh:mm"); color: folio.ink
            font.family: "Jacquard 24"; font.pixelSize: folio.width*.14
            font.letterSpacing: -folio.width*.005; font.weight: Font.Normal
            lineHeight: .88
        }
        Text {
            topPadding: folio.height*.012
            text: Qt.formatDateTime(clock.date,"dddd, d MMMM").toUpperCase(); color: folio.ink
            font.family: "IBM Plex Mono"; font.pixelSize: Math.max(12,folio.width*.0104)
        }
        Text {
            text: "A quiet place to begin."; color: folio.muted
            font.family: "IBM Plex Mono"; font.pixelSize: Math.max(11,folio.width*.0094)
        }
    }
    Column {
        x: folio.contentX; y: folio.authY - Math.max(49, folio.height*.055); spacing: 7
        Text { text: folio.userLabel; color: folio.ink; font.family: "IBM Plex Mono"; font.pixelSize: Math.max(12,folio.width*.010); font.letterSpacing: 1 }
        Text { text: "@hostname@ · NIRI".toUpperCase(); color: folio.muted; font.family: "IBM Plex Mono"; font.pixelSize: Math.max(10,folio.width*.0075); font.letterSpacing: 1 }
    }
    Text {
        x: folio.contentX; y: folio.height*.95
        text: (folio.state.collectionName || "Doré") + " / " + (folio.state.ink || "azure").toUpperCase() + " / " + (folio.state.mode === "dark" ? "AFTER HOURS" : "DAYLIGHT")
        color: folio.ink; font.family: "IBM Plex Mono"; font.pixelSize: Math.max(9,folio.width*.0064)
    }
}
