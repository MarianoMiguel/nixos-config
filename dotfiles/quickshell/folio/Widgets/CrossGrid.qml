import QtQuick
import qs.Common

// The password field: a cross of 13 hairline cells (rows 1 · 3 · 5 · 3 · 1).
// Each typed character prints one cell in halftone ink, spiralling out from
// the centre; deleting lifts the last. peek shows the characters on solid
// ink, flood() prints every cell solid (accepted), shake() is the refusal.
Item {
    id: root
    property real cell: 44
    property int count: 0                   // characters typed
    property string text: ""                // only read while peeking
    property bool peek: false
    property bool caret: true
    readonly property int size: 13

    implicitWidth: cell * 5
    implicitHeight: cell * 5

    // [row, column] of each cell in print order: the centre, then outward.
    readonly property var order: [[2, 2], [1, 2], [2, 3], [3, 2], [2, 1], [1, 3], [3, 3], [3, 1], [1, 1], [0, 2], [2, 4], [4, 2], [2, 0]]

    property int floodStep: -1
    function flood() { floodStep = 0; floodTimer.restart(); }
    function reset() { floodTimer.stop(); floodStep = -1; }
    Timer {
        id: floodTimer
        interval: Math.max(1, 22 * Theme.motion); repeat: true
        onTriggered: { root.floodStep++; if (root.floodStep >= root.size) stop(); }
    }

    // The refusal: pulled left, then let go; the spring rings out.
    function shake() { shakeX = -11 * Theme.motion; release.restart(); }
    property real shakeX: 0
    Behavior on shakeX { SpringAnimation { spring: 18; damping: 0.16; epsilon: 0.2 } }
    Timer { id: release; interval: 50; onTriggered: root.shakeX = 0 }
    transform: Translate { x: root.shakeX }

    Repeater {
        model: root.order
        Item {
            id: c
            required property var modelData
            required property int index
            readonly property bool on: index < root.count || flooded
            readonly property bool flooded: root.floodStep >= index
            x: modelData[1] * root.cell
            y: modelData[0] * root.cell
            width: root.cell
            height: root.cell

            property real ink: 0
            property real solid: 0
            onOnChanged: go(inkAnim, on ? 1 : 0, on ? 260 : 200)
            onFloodedChanged: if (flooded) go(solidAnim, 1, 180); else { solidAnim.stop(); solid = 0; }
            Component.onCompleted: ink = on ? 1 : 0
            function go(anim, value, ms) {
                anim.stop();
                anim.to = value;
                anim.duration = Math.max(1, ms * Theme.motion);
                anim.start();
            }
            NumberAnimation { id: inkAnim; target: c; property: "ink" }
            NumberAnimation { id: solidAnim; target: c; property: "solid" }

            // Hairlines: each cell draws its edge one pixel wide on the
            // boundary, so shared edges darken a little, as in the kit.
            Rectangle {
                x: 0; y: 0
                width: root.cell + 1; height: root.cell + 1
                color: "transparent"
                border.width: 1
                border.color: Theme.ruleStrong
            }
            Halftone {
                anchors.fill: parent
                anchors.margins: 3
                visible: c.ink > 0 || c.solid > 0
                progress: c.ink
                solid: root.peek && c.on ? 1 : c.solid
                seed: c.index * 7 + 3
            }
            Text {
                anchors.centerIn: parent
                visible: root.peek && c.on && !c.flooded
                text: root.text.charAt(c.index)
                color: Theme.inkText
                font.family: Theme.mono
                font.pixelSize: 15
                font.weight: Font.Medium
            }
        }
    }

    // The caret: a dot breathing in the centre cell while nothing is typed.
    Rectangle {
        x: 2.5 * root.cell - 3.5
        y: 2.5 * root.cell - 3.5
        width: 7; height: 7; radius: 3.5
        color: Theme.ink
        visible: root.caret && root.count === 0 && root.floodStep < 0
        SequentialAnimation on scale {
            running: parent.visible; loops: Animation.Infinite
            NumberAnimation { to: 0.4; duration: 600; easing.type: Easing.InOutCubic }
            NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutCubic }
        }
        SequentialAnimation on opacity {
            running: parent.visible; loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutCubic }
            NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutCubic }
        }
    }
}
