import QtQuick
import qs.Common
import qs.Widgets

// A text field: placeholder, optional password mode (with a show toggle),
// Enter accepts, Escape cancels. focusNow() puts the caret in it.
Item {
    id: root
    property alias text: input.text
    property string placeholder
    property bool password: false
    property bool reveal: false
    property string icon
    property bool error: false                 // a red ring: wrong password, invalid value
    readonly property alias input: input
    signal accepted(string text)
    signal cancelled()
    function focusNow() { input.forceActiveFocus(); input.selectAll(); }
    implicitWidth: 240
    implicitHeight: 34

    Rectangle {
        anchors.fill: parent
        radius: Theme.rS
        color: Theme.sheetStrong
        border.width: input.activeFocus || root.error ? 2 : 1
        border.color: root.error ? Theme.error : input.activeFocus ? Theme.ink : Theme.ruleStrong
    }
    Icon {
        id: lead
        visible: root.icon !== ""
        x: 10; anchors.verticalCenter: parent.verticalCenter
        name: root.icon; size: 15; color: Theme.text3
    }
    TextInput {
        id: input
        anchors { left: parent.left; right: eye.visible ? eye.left : parent.right; verticalCenter: parent.verticalCenter
                  leftMargin: lead.visible ? 32 : 11; rightMargin: 8 }
        color: Theme.text
        selectionColor: Theme.rgba(Theme.ink, 0.3)
        selectedTextColor: Theme.text
        font.family: Theme.ui
        font.pixelSize: Theme.fsM
        clip: true
        echoMode: root.password && !root.reveal ? TextInput.Password : TextInput.Normal
        onAccepted: root.accepted(text)
        Keys.onEscapePressed: event => { root.cancelled(); input.focus = false; event.accepted = true; }
        Label {
            visible: input.text === "" && !input.preeditText
            text: root.placeholder
            color: Theme.text3
            width: parent.width
        }
    }
    Icon {
        id: eye
        visible: root.password
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        name: "eye"; size: 15; color: root.reveal ? Theme.ink : Theme.text3
        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: root.reveal = !root.reveal }
    }
}
