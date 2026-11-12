import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// A Sound page row whose control is wide: the ink badge, a name and hint in a
// fixed column, then the control filling the rest. Volume, balance and the
// level meter share these columns, so their tracks line up:
// [41 px lead] [track, fills] [42 px tail].
Item {
    id: root
    property string icon
    property string label
    property string hint
    default property alias control: slot.data
    Layout.fillWidth: true
    implicitHeight: Math.max(56, text.implicitHeight + 20)

    RowLayout {
        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
        Rectangle {
            Layout.preferredWidth: 30; Layout.preferredHeight: 30; radius: 9; color: Theme.ink
            Icon { anchors.centerIn: parent; name: root.icon; size: 16; color: Theme.inkText }
        }
        ColumnLayout {
            id: text
            Layout.fillWidth: false; Layout.preferredWidth: 150; Layout.minimumWidth: 0; spacing: 1
            Label { text: root.label; font.weight: Font.Medium; Layout.fillWidth: true }
            Label { visible: root.hint !== ""; text: root.hint; color: Theme.text2; font.pixelSize: Theme.fsS; Layout.fillWidth: true }
        }
        RowLayout { id: slot; Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 12 }
    }
}
