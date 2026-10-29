import QtQuick
import qs.Common
import qs.Widgets

// A small button on the thumbnail: a word or a glyph on paper; hover inks it
// (red for a destructive one), a press sinks it.
Rectangle {
    id: root
    property string text: ""
    property string glyph: ""
    property bool danger: false
    signal clicked()

    readonly property bool hot: area.containsMouse
    width: glyph ? 26 : label.implicitWidth + 20
    height: 26
    radius: Theme.inner(Theme.inner(Theme.rL, 6), 6)
    color: hot ? (danger ? Theme.error : Theme.ink) : Theme.sheetStrong
    border.width: 1
    border.color: hot ? "transparent" : Theme.rule
    scale: area.pressed ? 0.94 : 1
    Behavior on scale { SpringPress {} }
    Behavior on color { ColorAnimation { duration: Theme.tQuick } }

    Label {
        id: label
        visible: !root.glyph
        anchors.centerIn: parent
        text: root.text
        font.pixelSize: Theme.fsS
        font.weight: Font.Medium
        color: root.hot ? Theme.inkText : root.danger ? Theme.error : Theme.text
    }
    Icon {
        visible: root.glyph !== ""
        anchors.centerIn: parent
        name: root.glyph
        size: 13
        color: root.hot ? Theme.inkText : Theme.text
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
