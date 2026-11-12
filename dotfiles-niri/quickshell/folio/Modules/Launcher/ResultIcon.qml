import QtQuick
import Quickshell
import qs.Common
import qs.Widgets

// A result's picture: the app's own icon as shipped, an emoji as it is, or a
// Folio glyph on an ink-tinted tile (actions, calculator, clipboard, files,
// web, apps without one).
Item {
    id: root
    property string icon            // desktop entry icon: theme name or path
    property string glyph: "grid"
    property string mark            // a character instead of a glyph ("=")
    property string emoji           // an emoji, drawn bare (no tile)
    property real size: 28
    property bool inverted: false       // on the ink selection
    property bool filled: false         // a solid ink tile (the preview)
    implicitWidth: size
    implicitHeight: size

    readonly property string source: {
        if (!icon) return "";
        if (icon.startsWith("/")) return "file://" + icon;
        if (icon.startsWith("file://")) return icon;
        return Quickshell.iconPath(icon, true);
    }
    readonly property bool hasImage: source !== "" && img.status !== Image.Error

    Text {
        anchors.centerIn: parent
        visible: root.emoji !== ""
        text: root.emoji
        font.pixelSize: Math.round(root.size * 0.82)
        textFormat: Text.PlainText
    }

    Image {
        id: img
        anchors.fill: parent
        visible: root.hasImage
        source: root.source
        sourceSize: Qt.size(Math.ceil(root.size * 2), Math.ceil(root.size * 2))
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
    }
    Rectangle {
        anchors.fill: parent
        visible: !root.hasImage && root.emoji === ""
        radius: Math.round(root.size * 0.29)
        color: root.filled ? Theme.ink : root.inverted ? Theme.rgba(Theme.paper, 0.2) : Theme.rgba(Theme.ink, 0.13)
        Icon {
            anchors.centerIn: parent
            visible: !root.mark
            name: root.glyph
            size: Math.round(root.size * 0.58)
            stroke: root.size > 40 ? 1.4 : 1.6
            color: root.inverted || root.filled ? Theme.paper : Theme.ink
        }
        Text {
            anchors.centerIn: parent
            visible: root.mark !== ""
            text: root.mark
            color: root.inverted || root.filled ? Theme.paper : Theme.ink
            font.family: Theme.mono
            font.weight: Font.Medium
            font.pixelSize: Math.round(root.size * 0.6)
            textFormat: Text.PlainText
        }
    }
}
