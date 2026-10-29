import QtQuick
import Quickshell
import qs.Common

// An app's icon as shipped (a theme name or a path); without one, the app's
// initial on an ink-tinted tile. Used by Notifications and Default apps.
Item {
    id: root
    property string icon
    property string name
    property real size: 30
    implicitWidth: size
    implicitHeight: size

    readonly property string source: {
        if (!icon) return "";
        if (icon.startsWith("/")) return "file://" + icon;
        if (icon.indexOf("://") > 0) return icon;
        return Quickshell.iconPath(icon, true);
    }
    readonly property bool shows: source !== "" && img.status === Image.Ready

    Image {
        id: img
        anchors.fill: parent
        visible: root.shows
        source: root.source
        sourceSize: Qt.size(Math.ceil(root.size * 2), Math.ceil(root.size * 2))
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
    }
    Rectangle {
        anchors.fill: parent
        visible: !root.shows
        radius: Math.round(root.size * 0.3)
        color: Theme.rgba(Theme.ink, 0.13)
        Text {
            anchors.centerIn: parent
            text: (root.name || "?").trim().charAt(0).toUpperCase()
            color: Theme.ink
            font.family: Theme.ui
            font.weight: Font.DemiBold
            font.pixelSize: Math.round(root.size * 0.46)
            textFormat: Text.PlainText
        }
    }
}
