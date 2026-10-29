import QtQuick
import qs.Common

// A switch: the knob slides on a spring, the track inks in.
Item {
    id: root
    property bool checked: false
    signal toggled(bool value)
    implicitWidth: 40; implicitHeight: 24

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Theme.ink : Theme.wellStrong
        Behavior on color { ColorAnimation { duration: Theme.tQuick } }
    }
    Rectangle {
        width: 20; height: 20; radius: 10
        y: 2
        x: root.checked ? root.width - width - 2 : 2
        color: root.checked ? Theme.paper : Theme.sheetBase
        Behavior on x { SpringPress {} }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggled(!root.checked) }
}
