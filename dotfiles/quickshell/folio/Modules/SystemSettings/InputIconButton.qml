import QtQuick
import qs.Common
import qs.Widgets

// A small icon button for a row's own actions (move up, move down, remove).
// Sinks like a stamp when pressed; fades when it cannot act.
Item {
    id: root
    property string icon
    property real turn: 0               // degrees, e.g. 180 turns "down" into up
    property string label               // what it does, for search and tests
    signal clicked()
    implicitWidth: 28
    implicitHeight: 28
    opacity: enabled ? 1 : 0.3
    scale: area.pressed || keyDown.running ? 0.9 : 1
    activeFocusOnTab: true
    Keys.onPressed: event => KeyNav.press(event, () => { keyDown.restart(); root.clicked(); })
    Timer { id: keyDown; interval: 110 }
    Behavior on scale { SpringPress {} }
    Behavior on opacity { NumberAnimation { duration: Theme.tQuick } }

    Rectangle {
        anchors.fill: parent
        radius: Theme.inner(Theme.rS, 2)
        color: area.containsMouse && root.enabled ? Theme.wellStrong : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.tQuick } }
    }
    Icon { anchors.centerIn: parent; name: root.icon; size: 15; rotation: root.turn; color: area.containsMouse ? Theme.ink : Theme.text2 }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
    FocusRing { radius: Theme.inner(Theme.rS, 2) }
}
