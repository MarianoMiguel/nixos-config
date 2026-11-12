import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// A settings row: ink badge, label and hint, and a control on the right.
Item {
    id: root
    property string icon
    property string label
    property string hint
    default property alias control: slot.data
    implicitHeight: Math.max(56, text.implicitHeight + 20)
    Layout.fillWidth: true

    RowLayout {
        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
        Rectangle {
            Layout.preferredWidth: 30; Layout.preferredHeight: 30; radius: 9; color: Theme.ink
            Icon { anchors.centerIn: parent; name: root.icon; size: 16; color: Theme.inkText }
        }
        ColumnLayout {
            id: text
            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 1
            Label { text: root.label; font.weight: Font.Medium; Layout.fillWidth: true }
            Label { visible: root.hint !== ""; text: root.hint; color: Theme.text2; font.pixelSize: Theme.fsS; Layout.fillWidth: true }
        }
        Item { id: slot; implicitWidth: childrenRect.width; implicitHeight: childrenRect.height; Layout.alignment: Qt.AlignVCenter }
    }
}
