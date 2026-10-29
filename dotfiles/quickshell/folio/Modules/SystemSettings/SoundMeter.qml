import QtQuick
import qs.Common

// The input level as a row of segments, like the study's meter: ink when lit,
// the warning colour near the top, the error colour at clipping. Falls back
// quickly so speech reads as movement, not as a bar.
Item {
    id: root
    property real level: 0          // 0..1
    property bool dim: false
    property int count: 24
    implicitWidth: 260
    implicitHeight: 10

    property real shown: Math.max(0, Math.min(1, level))
    Behavior on shown { NumberAnimation { duration: Math.max(40, Theme.tPress); easing.type: Easing.OutCubic } }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Repeater {
            model: root.count
            Rectangle {
                required property int index
                readonly property real at: (index + 1) / root.count
                readonly property bool on: !root.dim && index < Math.round(root.shown * root.count)
                width: (root.width - (root.count - 1) * 2) / root.count
                height: 8
                radius: 2
                color: on && at > 0.92 ? Theme.error : on && at > 0.75 ? Theme.warning : Theme.ink
                opacity: on ? 1 : 0.15
            }
        }
    }
}
