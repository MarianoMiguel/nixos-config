import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// A choosable card: a preview, a name and a line; the ink ring and the tick
// arrive on a spring when it is chosen. Presses sink like a stamp.
Item {
    id: root
    property bool selected: false
    property string title
    property string subtitle
    default property alias preview: thumb.data
    property real previewRatio: 16 / 10
    signal chosen()
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 18
    scale: press.pressed ? 0.97 : 1
    Behavior on scale { SpringPress {} }

    Rectangle {
        anchors.fill: parent; radius: 16; color: Theme.well
        border.width: root.selected ? 2 : 1
        border.color: root.selected ? Theme.ink : (press.containsMouse ? Theme.ruleStrong : Theme.rule)
    }
    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        spacing: 7
        Item {
            id: thumb
            Layout.fillWidth: true
            Layout.preferredHeight: width / root.previewRatio
            clip: true
        }
        Label { text: root.title; font.weight: Font.DemiBold; Layout.leftMargin: 4; Layout.fillWidth: true }
        Label { visible: root.subtitle !== ""; text: root.subtitle; color: Theme.text2; font.pixelSize: Theme.fsS - 0.5; Layout.leftMargin: 4; Layout.fillWidth: true; Layout.topMargin: -5 }
    }
    Rectangle {
        anchors { top: parent.top; right: parent.right; margins: 14 }
        width: 22; height: 22; radius: 11; color: Theme.ink
        scale: root.selected ? 1 : 0
        Behavior on scale { SpringPress {} }
        Icon { anchors.centerIn: parent; name: "check"; size: 13; stroke: 2.4; color: Theme.inkText }
    }
    MouseArea { id: press; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.chosen() }
}
