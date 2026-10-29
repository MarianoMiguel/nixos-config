import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Widgets

// The kit's range: a pill filled with ink up to the value, its icon inside
// the fill (it turns to text color when the fill is too short to hold it).
// Drag or click to set; the wheel steps by 5%.
Item {
    id: root

    property real value: 0              // 0..1
    property string icon
    property bool dim: false            // muted: the fill fades
    signal moved(real v)

    property bool dragging: area.pressed
    property real dragValue: 0
    readonly property real shown: dragging ? dragValue : Math.max(0, Math.min(1, value))

    implicitHeight: 30

    function at(x) { return Math.max(0, Math.min(1, x / Math.max(1, width))); }

    ClippingRectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.wellStrong
        Rectangle {
            id: fill
            height: parent.height
            width: root.shown * root.width
            color: Theme.ink
            opacity: root.dim ? 0.45 : 1
            Behavior on width { enabled: !root.dragging; SpringPanel {} }
        }
    }
    Icon {
        x: 11
        anchors.verticalCenter: parent.verticalCenter
        name: root.icon
        size: 17
        color: fill.width > 24 && !root.dim ? Theme.inkText : Theme.text2
    }
    MouseArea {
        id: area
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: mouse => { root.dragValue = root.at(mouse.x); root.moved(root.dragValue); }
        onPositionChanged: mouse => { if (pressed) { root.dragValue = root.at(mouse.x); root.moved(root.dragValue); } }
        onWheel: wheel => root.moved(Math.max(0, Math.min(1, Math.round((root.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05)) * 100) / 100)))
    }
}
