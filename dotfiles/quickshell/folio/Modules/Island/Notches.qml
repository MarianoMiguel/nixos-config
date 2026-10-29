import QtQuick
import qs.Common

// Level feedback as sixteen notches; the last lit one stands taller.
Row {
    id: root

    property real value: 0
    readonly property int lit: Math.round(Math.max(0, Math.min(1, value)) * 16)
    spacing: 3

    Repeater {
        model: 16
        Rectangle {
            required property int index
            readonly property bool on: index < root.lit
            width: 6
            height: 10
            radius: 2
            anchors.verticalCenter: parent.verticalCenter
            color: on ? Theme.islandInk : Theme.rgba(Theme.islandText, 0.16)
            Behavior on color { ColorAnimation { duration: Theme.tPress } }
            transform: Scale {
                origin.y: 5
                yScale: index === root.lit - 1 ? 1.35 : 1
                Behavior on yScale { SpringPress {} }
            }
        }
    }
}
