import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// A caption over a card ("World clock · …"): mono caps, left and right.
Item {
    id: root
    property string title
    property string note
    implicitHeight: 18
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        anchors.topMargin: 2
        spacing: 12
        Cap { text: root.title; Layout.fillWidth: true; Layout.minimumWidth: 0 }
        Cap { text: root.note; visible: text !== ""; Layout.maximumWidth: root.width / 2 }
    }
}
