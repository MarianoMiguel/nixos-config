import QtQuick
import qs.Common
import qs.Widgets

// A switch: the knob slides on a spring, the track inks in. Space or Enter
// flips it when it has keyboard focus.
Item {
    id: root
    property bool checked: false
    signal toggled(bool value)
    implicitWidth: 40; implicitHeight: 24
    activeFocusOnTab: true
    Keys.onPressed: event => KeyNav.press(event, () => root.toggled(!root.checked))

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
    FocusRing { radius: root.height / 2 }
}
