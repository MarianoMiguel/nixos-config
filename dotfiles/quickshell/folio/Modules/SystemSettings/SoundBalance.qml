import QtQuick
import qs.Common
import qs.Widgets

// Left–right balance: the ink fills from the centre to the knob, a mark shows
// the middle, and the knob snaps to it when close. Drag or click to set; the
// wheel and arrow keys step; a double click centres. Values run -1..1. The
// track sits where Slider's does (8 px in from each side), so they line up.
Item {
    id: root
    property real value: 0
    property real step: 0.1
    signal moved(real v)

    readonly property bool dragging: area.pressed
    property real dragValue: 0
    readonly property real shown: Math.max(-1, Math.min(1, dragging ? dragValue : value))
    implicitWidth: 260
    implicitHeight: 24
    activeFocusOnTab: true

    readonly property real span: track.width
    function at(x) {
        const v = Math.max(-1, Math.min(1, (x - track.x) / Math.max(1, span) * 2 - 1));
        return Math.abs(v) < 0.06 ? 0 : Math.round(v * 100) / 100;
    }
    function nudge(d) { root.moved(Math.max(-1, Math.min(1, Math.round((root.value + d) * 100) / 100))); }
    Keys.onLeftPressed: nudge(-step)
    Keys.onRightPressed: nudge(step)

    Rectangle {
        id: track
        x: 8; width: parent.width - 16; height: 6; radius: 3
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.wellStrong
        Rectangle {
            readonly property real mid: parent.width / 2
            readonly property real end: (root.shown + 1) / 2 * parent.width
            x: Math.min(mid, end); width: Math.abs(end - mid); height: parent.height; radius: 3
            color: Theme.ink
            Behavior on x { enabled: !root.dragging; SpringPanel {} }
            Behavior on width { enabled: !root.dragging; SpringPanel {} }
        }
        Rectangle { x: parent.width / 2 - 1; y: -3; width: 2; height: 12; radius: 1; color: Theme.ruleStrong }
    }
    Rectangle {
        width: 18; height: 18; radius: 9
        anchors.verticalCenter: parent.verticalCenter
        x: track.x + (root.shown + 1) / 2 * track.width - width / 2
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
        onPressed: mouse => { root.forceActiveFocus(); root.dragValue = root.at(mouse.x); root.moved(root.dragValue); }
        onPositionChanged: mouse => { if (pressed) { root.dragValue = root.at(mouse.x); root.moved(root.dragValue); } }
        onDoubleClicked: root.moved(0)
        onWheel: wheel => root.nudge(wheel.angleDelta.y > 0 ? root.step : -root.step)
    }
}
