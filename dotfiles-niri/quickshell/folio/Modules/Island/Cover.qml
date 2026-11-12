import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// Album art as the app ships it; a printed plate when there is none (or
// when Folio prints app imagery).
ClippingRectangle {
    id: root

    property string source: ""
    readonly property bool printed: Settings.get("dock.icons") === "printed"
    readonly property bool hasArt: !printed && source !== "" && img.status === Image.Ready
    color: Theme.rgba(Theme.islandText, 0.1)

    Plate {
        anchors.fill: parent
        visible: !root.hasArt
        plate: Art.plate("argentina-buenos-aires") ? "argentina-buenos-aires" : Art.current
        developOnLoad: false
        zoom: 2.2
    }
    Image {
        id: img
        anchors.fill: parent
        visible: root.hasArt
        source: root.printed ? "" : root.source
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(128, 128)
        smooth: true
        mipmap: true
    }
}
