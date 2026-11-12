import QtQuick
import qs.Common
import qs.Services

// Four equalizer bars that dance while music plays and settle when paused.
// They step twelve times a second, not every frame (the island would redraw
// at the display's rate for as long as music plays), and hold still while
// the lock covers them or the screens are off.
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

    // One loop is 900 ms.
    Timer {
        interval: 83; repeat: true
        running: root.visible && root.amp > 0.001 && !Unseen.desktop
        onTriggered: root.phase = (root.phase + interval / 900) % 1
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
