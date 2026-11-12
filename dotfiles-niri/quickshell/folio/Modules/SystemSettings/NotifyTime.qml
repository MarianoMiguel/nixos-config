import QtQuick
import qs.Common
import qs.Widgets

// A time of day as a stepper (the controls study): − 22:00 +. Steps of a
// quarter hour, wrapping past midnight; hold a button to keep stepping, or
// use the wheel and the arrow keys. value is minutes after midnight.
Item {
    id: root
    property int value: 0
    property int step: 15
    signal moved(int value)
    implicitWidth: 118
    implicitHeight: 32
    activeFocusOnTab: true
    opacity: enabled ? 1 : 0.5

    function hm(m) { return String(Math.floor(m / 60)).padStart(2, "0") + ":" + String(m % 60).padStart(2, "0"); }
    function nudge(d) {
        const snapped = Math.round(root.value / root.step) * root.step;
        root.moved(((snapped + d * root.step) % 1440 + 1440) % 1440);
    }
    Keys.onPressed: event => {
        KeyNav.key();
        if (!KeyNav.plain(event)) return;
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Right) nudge(1);
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_Left) nudge(-1);
        else return;
        event.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.rS
        color: Theme.well
        border.width: 1
        border.color: Theme.rule
    }
    FocusRing { radius: Theme.rS }
    MouseArea {
        anchors.fill: parent
        onWheel: wheel => root.nudge(wheel.angleDelta.y > 0 ? 1 : -1)
    }
    Step { anchors.left: parent.left; dir: -1; glyph: "minus" }
    Text {
        anchors.centerIn: parent
        text: root.hm(root.value)
        color: Theme.text
        font.family: Theme.ui
        font.pixelSize: Theme.fsM
        font.weight: Font.DemiBold
        font.features: ({ "tnum": 1 })
    }
    Step { anchors.right: parent.right; dir: 1; glyph: "plus" }

    component Step: Item {
        id: btn
        property int dir: 1
        property string glyph
        width: 32
        height: root.height
        Icon {
            anchors.centerIn: parent
            name: btn.glyph
            size: 14
            stroke: 2
            color: Theme.ink
            scale: press.pressed ? 0.8 : 1
            Behavior on scale { SpringPress {} }
        }
        MouseArea {
            id: press
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: { root.forceActiveFocus(); root.nudge(btn.dir); hold.interval = 420; hold.start(); }
            onReleased: hold.stop()
            onCanceled: hold.stop()
        }
        Timer { id: hold; repeat: true; onTriggered: { interval = 80; root.nudge(btn.dir); } }
    }
}
