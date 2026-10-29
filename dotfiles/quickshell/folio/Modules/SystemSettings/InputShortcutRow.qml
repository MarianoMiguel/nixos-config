import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// One keybind, read only: what it does, the action and the file it is set in,
// and its keys as caps on the right.
Item {
    id: root
    property string title
    property string detail
    property var caps: []
    Layout.fillWidth: true
    implicitHeight: Math.max(48, text.implicitHeight + 16)

    RowLayout {
        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
        ColumnLayout {
            id: text
            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 1
            Label { text: root.title; font.weight: Font.Medium; Layout.fillWidth: true }
            Label { visible: root.detail !== ""; text: root.detail; color: Theme.text3; font.pixelSize: Theme.fsS - 0.5; font.family: Theme.mono; Layout.fillWidth: true }
        }
        InputKeys { caps: root.caps; Layout.alignment: Qt.AlignVCenter }
    }
}
