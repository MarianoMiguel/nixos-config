import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Widgets

// A range: a track filled with ink up to the value, a knob that grows while
// held. Drag or click to set; the wheel and arrow keys step. Values run from
// 0 to `to` (1 by default; 1.5 for volume with over-amplification); a mark
// shows where 1 is when `to` is above it.
Item {
    id: root
    property real value: 0
    property real to: 1
    property real step: 0.05
    property bool dim: false
    signal moved(real v)

    readonly property bool dragging: area.pressed
    property real dragValue: 0
    readonly property real shown: Math.max(0, Math.min(to, dragging ? dragValue : value))
    implicitWidth: 220
    implicitHeight: 24
    activeFocusOnTab: true

    function at(x) { return Math.max(0, Math.min(root.to, Math.round(x / Math.max(1, width - 16) * root.to / 0.01) * 0.01)); }
    function nudge(d) { root.moved(Math.max(0, Math.min(root.to, Math.round((root.value + d) * 100) / 100))); }
    Keys.onLeftPressed: nudge(-step)
    Keys.onRightPressed: nudge(step)

    Rectangle {
        id: track
        x: 8; width: parent.width - 16; height: 6; radius: 3
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.wellStrong
        Rectangle {
            height: parent.height; radius: 3
            width: root.shown / root.to * parent.width
            color: Theme.ink
            opacity: root.dim ? 0.45 : 1
            Behavior on width { enabled: !root.dragging; SpringPanel {} }
        }
        Rectangle {
            visible: root.to > 1
            x: parent.width / root.to - 1; y: -3; width: 2; height: 12; radius: 1
            color: Theme.ruleStrong
        }
    }
    Rectangle {
        id: knob
        width: 18; height: 18; radius: 9
        anchors.verticalCenter: parent.verticalCenter
        x: track.x + root.shown / root.to * track.width - width / 2
        color: Theme.sheetBase
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Theme.ink : Theme.ruleStrong
        scale: root.dragging ? 1.15 : 1
        Behavior on scale { SpringPress {} }
        Behavior on x { enabled: !root.dragging; SpringPanel {} }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: mouse => { root.forceActiveFocus(); root.dragValue = root.at(mouse.x - 8); root.moved(root.dragValue); }
        onPositionChanged: mouse => { if (pressed) { root.dragValue = root.at(mouse.x - 8); root.moved(root.dragValue); } }
        onWheel: wheel => root.nudge(wheel.angleDelta.y > 0 ? root.step : -root.step)
    }
}
