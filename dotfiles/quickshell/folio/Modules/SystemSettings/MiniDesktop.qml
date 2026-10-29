import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

// The whole desktop in miniature, for previews: plate, bar, island, a window,
// the sidebar and the dock, drawn with the live tokens.
Item {
    id: root
    property string plate: ""
    property string forceMode: ""
    property bool sidebar: true
    property real breathe: 0
    readonly property real u: width / 100

    Plate { anchors.fill: parent; plate: root.plate || Art.current; forceMode: root.forceMode; breathe: root.breathe; textureWidth: 1600; developOnLoad: false }
    Rectangle { x: 0; y: 0; width: parent.width; height: root.u * 3.2; color: Theme.sheet
        Rectangle { x: root.u * 1.2; anchors.verticalCenter: parent.verticalCenter; width: root.u * 1.8; height: width; radius: width * 0.3; color: Theme.ink }
        Rectangle { x: root.u * 4; anchors.verticalCenter: parent.verticalCenter; width: root.u * 3; height: root.u * 0.7; radius: height / 2; color: Theme.ink }
        Rectangle { anchors.right: parent.right; anchors.rightMargin: root.u * 1.4; anchors.verticalCenter: parent.verticalCenter; width: root.u * 9; height: root.u * 1.1; radius: height / 2; color: Theme.wellStrong }
    }
    Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: root.u * 0.45; width: root.u * 13; height: root.u * 2.3; radius: height / 2; color: Theme.island }
    Rectangle {
        x: root.u * 2; y: root.u * 5; width: parent.width * 0.55; height: parent.height - root.u * 15
        radius: root.u * 0.9; color: Theme.sheetStrong; border.color: Theme.rule; clip: true
        Rectangle { width: parent.width; height: root.u * 2.6; color: Theme.mix(Theme.paper, Theme.ink, 0.18) }
        Repeater { model: [0.45, 0.7, 0.55]; Rectangle { required property var modelData; required property int index; x: root.u * 3; y: root.u * (5 + index * 2.2); width: parent.width * modelData; height: root.u * 0.9; radius: height / 2; color: Theme.wellStrong } }
    }
    Rectangle {
        visible: root.sidebar
        anchors { right: parent.right; rightMargin: root.u * 1.2; top: parent.top; topMargin: root.u * 4.6; bottom: parent.bottom; bottomMargin: root.u * 9 }
        width: root.u * 24; radius: root.u * 1.6; color: Theme.sheet; border.color: Theme.rule
        Column {
            anchors.fill: parent; anchors.margins: root.u * 1.4; spacing: root.u * 1.1
            Text { text: "22:41"; font.family: Theme.hero; font.pixelSize: root.u * 5.4; color: Theme.ink }
            Grid { columns: 2; spacing: root.u * 0.8
                Repeater { model: 4; Rectangle { required property int index; width: root.u * 10; height: root.u * 3.8; radius: root.u * 0.9; color: index < 2 ? Theme.ink : Theme.well } }
            }
            Rectangle { width: parent.width; height: root.u * 8; radius: root.u * 0.9; color: Theme.well }
        }
    }
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: root.u * 1.4
        width: dockRow.width + root.u * 2.4; height: root.u * 5.6; radius: root.u * 1.6; color: Theme.sheet; border.color: Theme.rule
        Row { id: dockRow; anchors.centerIn: parent; spacing: root.u * 0.8
            Repeater { model: 7; Rectangle { required property int index; width: root.u * 3.8; height: width; radius: width * 0.26; color: [1, 4].indexOf(index) >= 0 ? Theme.ink : Theme.sheetBase; border.color: Theme.rule } }
        }
    }
}
