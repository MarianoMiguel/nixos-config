import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets

Button {
    id: root
    property string label
    property string glyph: "speaker"
    property bool selected: false
    property string detail: ""
    ToolTip.visible: hovered
    ToolTip.text: label
    ToolTip.delay: 700
    leftPadding: 0
    rightPadding: 0
    topPadding: 8
    bottomPadding: 8
    implicitHeight: detail ? 58 : 44
    Accessible.name: label + (selected ? ", selected" : "")
    background: Rectangle {
        radius: Theme.cornerRadius
        color: root.selected ? Theme.surfaceContainerHighest : root.hovered ? Theme.surfaceContainerHigh : Theme.surfaceContainer
        border.width: root.selected || root.visualFocus ? 1 : 0
        border.color: Theme.primary
    }
    contentItem: Row {
        spacing: 12
        DankIcon {
            name: root.glyph; size: 20
            color: Theme.primary; anchors.verticalCenter: parent.verticalCenter
        }
        Column {
            width: parent.width - 60; spacing: 3
            anchors.verticalCenter: parent.verticalCenter
            StyledText {
                width: parent.width; text: root.label
                color: Theme.surfaceText; font.pixelSize: 12
                font.weight: root.selected ? Font.Medium : Font.Normal
                elide: Text.ElideRight; wrapMode: Text.NoWrap
            }
            StyledText {
                width: parent.width; text: root.detail; visible: text.length > 0
                color: Theme.surfaceVariantText; font.pixelSize: 10
                elide: Text.ElideRight; wrapMode: Text.NoWrap
            }
        }
        DankIcon {
            name: "check"; size: 16; visible: root.selected
            color: Theme.primary; anchors.verticalCenter: parent.verticalCenter
        }
    }
}
