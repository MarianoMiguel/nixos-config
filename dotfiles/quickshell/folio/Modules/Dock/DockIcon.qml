import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell.Widgets
import qs.Common
import qs.Widgets

// An app icon as the dock shows it: as shipped (original); on a paper tile
// (plated); on the tile and in the ink (printed). On a tile every icon sits
// at the same inset; a square one is clipped to a corner concentric with the
// tile's. Drawn at the magnified size and scaled down, so it stays sharp
// when it grows.
Item {
    id: root
    property string source
    property string name
    property string glyph: ""               // Folio icon when there is no app icon
    property string mode: "original"        // original | plated | printed
    property string shape: ""               // square | free | "" (not probed yet)
    property real unit: 1                   // pixels per logical pixel at rest
    property real corner: 0.3               // tile corner / size, from the dock's radius and inset
    property var probe: null                // function(source): learn its shape

    readonly property bool missing: !source || img.status === Image.Error
    readonly property bool tiled: missing || mode !== "original"
    readonly property real inset: tiled ? width * 0.15 : 0
    readonly property bool printed: mode === "printed" && !missing
    readonly property real dpr: Screen.devicePixelRatio || 1

    onSourceChanged: if (source && !shape && probe) probe(source)
    Component.onCompleted: if (source && !shape && probe) probe(source)

    // The paper tile (plated and printed round or free-form icons).
    RectangularShadow {
        anchors.fill: tile
        visible: tile.visible
        radius: tile.radius
        blur: 6 * root.unit
        offset: Qt.vector2d(0, 2 * root.unit)
        color: Theme.rgba(Theme.shade, 0.16)
    }
    Rectangle {
        id: tile
        anchors.fill: parent
        visible: root.tiled
        radius: width * root.corner
        color: Theme.sheetBase
        border.width: root.unit
        border.color: Theme.rule
        Rectangle {
            anchors.fill: parent
            anchors.margins: root.unit
            radius: Math.max(0, parent.radius - root.unit)
            color: "transparent"
            border.width: root.unit
            border.color: Theme.highlight
            opacity: 0.6
        }
    }

    // The icon as it will be drawn: on a tile, a square icon loses its own
    // corners for the tile's less the inset (Theme.inner's rule).
    Item {
        id: art
        anchors.fill: parent
        anchors.margins: root.inset
        visible: false
        layer.enabled: true
        ClippingRectangle {
            anchors.fill: parent
            color: "transparent"
            radius: root.tiled && root.shape === "square" ? Math.max(0, root.width * root.corner - root.inset) : 0
            Image {
                id: img
                anchors.fill: parent
                source: root.source
                sourceSize: Qt.size(Math.round(root.width * root.dpr), Math.round(root.height * root.dpr))
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                mipmap: true
            }
        }
    }
    MultiEffect {
        anchors.fill: art
        source: art
        visible: !root.printed && img.status === Image.Ready
        shadowEnabled: !root.tiled
        shadowColor: Theme.rgba(Theme.shade, 0.28)
        shadowBlur: 0.15
        shadowVerticalOffset: 2 * root.unit
        shadowHorizontalOffset: 0
    }
    ShaderEffect {
        anchors.fill: art
        visible: root.printed && img.status === Image.Ready
        property var source: art
        // Light: ink on paper, mids pushed dark. Dark: the ink lifted toward
        // the text, mids pushed light, so colorful icons still read on night.
        property color lo: Theme.dark ? Theme.paper : Theme.ink
        property color hi: Theme.dark ? Theme.mix(Theme.ink, Theme.text, 0.5) : Theme.paper
        property real gamma: Theme.dark ? 0.55 : 1.9
        fragmentShader: Qt.resolvedUrl("../../shaders/duotone.frag.qsb")
    }

    // No icon: the app's initial, or a Folio glyph, printed on the tile.
    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: parent.height * 0.03
        visible: root.missing && !root.glyph
        text: (root.name || "?").charAt(0).toUpperCase()
        font.family: Theme.hero
        font.pixelSize: parent.height * 0.6
        color: Theme.ink
    }
    Icon {
        anchors.centerIn: parent
        visible: root.missing && root.glyph !== ""
        name: root.glyph
        size: parent.width * 0.52
        stroke: 1.7
        color: Theme.ink
    }
}
