import QtQuick
import qs.Common
import qs.Widgets

// A button: plain (on the well) or primary (ink). Sinks like a stamp when pressed.
Item {
    id: root
    property string text
    property string icon
    property bool primary: false
    property bool busy: false
    signal clicked()
    implicitWidth: row.implicitWidth + 26
    implicitHeight: 32
    opacity: enabled ? 1 : 0.45
    scale: area.pressed ? 0.96 : 1
    Behavior on scale { SpringPress {} }

    Rectangle {
        anchors.fill: parent
        radius: Theme.rS
        color: root.primary ? Theme.ink : (area.containsMouse ? Theme.wellStrong : Theme.well)
        border.width: root.primary ? 0 : 1
        border.color: Theme.rule
        Behavior on color { ColorAnimation { duration: Theme.tQuick } }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Icon {
            visible: root.icon !== "" || root.busy
            anchors.verticalCenter: parent.verticalCenter
            name: root.busy ? "reload" : root.icon
            size: 15
            color: root.primary ? Theme.inkText : Theme.ink
            RotationAnimation on rotation { running: root.busy; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
        }
        Label {
            visible: root.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            font.pixelSize: Theme.fsS
            font.weight: Font.Medium
            color: root.primary ? Theme.inkText : Theme.text
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled && !root.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
