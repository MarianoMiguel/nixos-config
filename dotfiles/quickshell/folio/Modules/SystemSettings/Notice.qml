import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// A quiet line for empty and unavailable states ("Bluetooth is off", "No
// displays found"), with an optional action button.
Rectangle {
    id: root
    property string icon: "info"
    property string text
    property string action
    signal acted()
    Layout.fillWidth: true
    implicitHeight: Math.max(52, body.implicitHeight + 24)
    radius: Theme.rM
    color: "transparent"
    border.color: Theme.rule
    RowLayout {
        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 10; spacing: 10
        Icon { name: root.icon; size: 16; color: Theme.text3 }
        Text {
            id: body
            // Plain: notices quote names from outside (files, devices, networks).
            text: root.text; textFormat: Text.PlainText; color: Theme.text2; font.family: Theme.ui; font.pixelSize: Theme.fsS
            wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Button { visible: root.action !== ""; text: root.action; onClicked: root.acted() }
    }
}
