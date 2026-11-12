import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// A section heading inside a page: a name and, optionally, one or two lines
// on what it does. Put a Card or controls right after it.
ColumnLayout {
    id: root
    property string title
    property string hint
    spacing: 2
    Layout.fillWidth: true
    Layout.topMargin: 26
    Layout.bottomMargin: 10
    Label { text: root.title; font.weight: Font.DemiBold; font.pixelSize: 15 * Theme.textScale; Layout.fillWidth: true }
    Text {
        visible: root.hint !== ""
        text: root.hint
        color: Theme.text2; font.family: Theme.ui; font.pixelSize: Theme.fsS
        wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
        Layout.fillWidth: true
    }
}
