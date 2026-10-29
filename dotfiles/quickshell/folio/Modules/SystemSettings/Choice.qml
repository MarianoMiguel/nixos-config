import QtQuick
import qs.Common
import qs.Widgets

// A segmented choice: the selected segment's thumb glides on a spring.
Item {
    id: root
    property var options: []            // [{value, label}]
    property var value
    signal chosen(var value)
    implicitHeight: 32
    implicitWidth: row.implicitWidth + 6

    Rectangle { anchors.fill: parent; radius: Theme.rS; color: Theme.well; border.color: Theme.rule; border.width: 1 }
    Rectangle {
        id: thumb
        readonly property int index: root.options.findIndex(o => o.value === root.value)
        readonly property Item target: index >= 0 && segments.count > index ? segments.itemAt(index) : null
        visible: target !== null
        y: 3; height: parent.height - 6
        x: target ? row.x + target.x : 3
        width: target ? target.width : 0
        radius: Theme.inner(Theme.rS, 3)
        color: Theme.sheetStrong
        border.color: Theme.rule; border.width: 1
        Behavior on x { SpringPanel {} }
        Behavior on width { SpringPanel {} }
    }
    Row {
        id: row
        x: 3; anchors.verticalCenter: parent.verticalCenter
        Repeater {
            id: segments
            model: root.options
            Item {
                required property var modelData
                implicitWidth: label.implicitWidth + 24; height: root.height - 6
                Label { id: label; anchors.centerIn: parent; text: modelData.label; font.pixelSize: Theme.fsS; color: root.value === modelData.value ? Theme.text : Theme.text2 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.chosen(modelData.value) }
            }
        }
    }
}
