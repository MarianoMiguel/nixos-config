import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// A command to run yourself (Storage & drives › Reclaim space): what it
// does, the command in mono, selectable, and Copy. The page never runs it.
Item {
    id: root
    property string title
    property string hint
    property string command
    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + 24

    ColumnLayout {
        id: column
        x: 14; y: 12
        width: parent.width - 28
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true; Layout.minimumWidth: 0
                spacing: 1
                Label { text: root.title; font.weight: Font.Medium; Layout.fillWidth: true }
                Text {
                    visible: root.hint !== ""
                    text: root.hint
                    color: Theme.text2; font.family: Theme.ui; font.pixelSize: Theme.fsS
                    wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
            Button {
                text: copied.running ? "Copied" : "Copy"
                Layout.alignment: Qt.AlignTop
                onClicked: { Clipboard.copy(root.command); copied.restart(); }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: code.implicitHeight + 16
            radius: Theme.rXs
            color: Theme.well
            border.color: Theme.rule
            TextEdit {
                id: code
                x: 10
                width: parent.width - 20
                anchors.verticalCenter: parent.verticalCenter
                text: root.command
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                textFormat: TextEdit.PlainText
                font.family: Theme.mono
                font.pixelSize: Theme.fsS
                color: Theme.text
                selectionColor: Theme.rgba(Theme.ink, 0.28)
                selectedTextColor: Theme.text
            }
        }
    }
    Timer { id: copied; interval: 1400 }
}
