import QtQuick
import qs.Common
import qs.Widgets

// The kit's .btn: a well (default), ink or ghost button with an icon, a
// label or both; round makes it a circle.
SideTap {
    id: root

    property string text
    property string icon
    property string kind: "well"        // well | ink | ghost
    property bool round: false
    property real size: 34
    property real iconSize: 18
    property real fontSize: Theme.fsM
    readonly property color fg: kind === "ink" ? Theme.inkText : Theme.text

    implicitHeight: size
    implicitWidth: round ? size : row.implicitWidth + 28
    radius: round ? size / 2 : Theme.rS

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.kind === "ink" ? Theme.ink : root.kind === "ghost" ? (root.hovered ? Theme.well : "transparent") : (root.hovered ? Theme.wellStrong : Theme.well)
        border.width: root.kind === "well" ? 1 : 0
        border.color: Theme.rule
        Behavior on color { ColorAnimation { duration: Theme.tQuick } }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Icon {
            visible: root.icon !== ""
            name: root.icon
            size: root.iconSize
            color: root.fg
            anchors.verticalCenter: parent.verticalCenter
        }
        Label {
            visible: root.text !== ""
            text: root.text
            color: root.fg
            font.pixelSize: root.fontSize
            font.weight: Font.Medium
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
