import QtQuick
import qs.Common

// Four equalizer bars that dance while music plays and settle when paused.
Item {
    id: root

    property bool playing: false
    property color color: Theme.islandInk
    property real phase: 0
    property real amp: playing ? 1 : 0
    Behavior on amp { SpringSoft {} }
    readonly property var offsets: [0, 0.333, 0.667, 0.167]

    implicitWidth: 3 * 4 + 2 * 3
    implicitHeight: 12

    NumberAnimation on phase {
        from: 0; to: 1; duration: 900; loops: Animation.Infinite
        running: root.visible && root.amp > 0.001
    }
    Row {
        anchors.bottom: parent.bottom
        spacing: 2
        Repeater {
            model: 4
            Rectangle {
                required property int index
                anchors.bottom: parent.bottom
                width: 3
                radius: 1.5
                color: root.color
                opacity: 0.55 + 0.45 * root.amp
                height: 4 + 8 * root.amp * (0.5 - 0.5 * Math.cos(2 * Math.PI * (root.phase + root.offsets[index])))
            }
        }
    }
}
