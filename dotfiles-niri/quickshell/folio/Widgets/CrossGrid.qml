import QtQuick
import qs.Common

// The password field. Folio: a cross of 13 hairline cells (rows 1 · 3 · 5 ·
// 3 · 1); each typed character prints one cell in halftone ink, spiralling
// out from the centre; deleting lifts the last. Lumen: a pill of dots with
// the accent's arrow. peek shows the characters, flood() fills the field
// with ink (accepted), shake() is the refusal.
Item {
    id: root
    property real cell: 44
    property int count: 0                   // characters typed
    property string text: ""                // only read while peeking
    property bool peek: false
    property bool caret: true
    readonly property int size: 13

    implicitWidth: Theme.prints ? cell * 5 : cell * 7.6
    implicitHeight: Theme.prints ? cell * 5 : Math.round(cell * 1.15)

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
        model: Theme.prints ? root.order : []
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
    // Its loops read their own item's visibility by id: inside an animation
    // `parent` is the grid's parent, so they ran while the caret was hidden
    // (and Lumen's caret in Folio, Folio's in Lumen), redrawing every frame.
    Rectangle {
        id: dotCaret
        x: 2.5 * root.cell - 3.5
        y: 2.5 * root.cell - 3.5
        width: 7; height: 7; radius: 3.5
        color: Theme.ink
        visible: Theme.prints && root.caret && root.count === 0 && root.floodStep < 0
        SequentialAnimation on scale {
            running: dotCaret.visible; loops: Animation.Infinite
            NumberAnimation { to: 0.4; duration: 600; easing.type: Easing.InOutCubic }
            NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutCubic }
        }
        SequentialAnimation on opacity {
            running: dotCaret.visible; loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutCubic }
            NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutCubic }
        }
    }

    // Lumen's field: dots in a pill, the accent's arrow at its end.
    Rectangle {
        visible: !Theme.prints
        anchors.fill: parent
        radius: height / 2
        color: root.floodStep >= 0 ? Theme.ink : Theme.well
        border.width: 1; border.color: Theme.rule
        Behavior on color { ColorAnimation { duration: Theme.tQuick } }
        Row {
            x: 20; anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            visible: !root.peek
            Repeater {
                model: Math.min(root.count, Math.max(0, Math.floor((root.width - 90) / 17)))
                Rectangle {
                    width: 9; height: 9; radius: 4.5
                    color: root.floodStep >= 0 ? Theme.inkText : Theme.text
                    NumberAnimation on scale { from: 0.2; to: 1; duration: Math.max(1, 140 * Theme.motion); easing.type: Easing.OutBack }
                }
            }
        }
        Text {
            visible: root.peek
            x: 20; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 80
            elide: Text.ElideLeft
            text: root.text
            color: root.floodStep >= 0 ? Theme.inkText : Theme.text
            font.family: Theme.ui; font.pixelSize: 16
        }
        // The caret, until something is typed.
        Rectangle {
            id: lineCaret
            x: 20; anchors.verticalCenter: parent.verticalCenter
            width: 2; height: parent.height * 0.42; radius: 1
            color: Theme.ink
            visible: root.caret && root.count === 0 && root.floodStep < 0
            SequentialAnimation on opacity {
                running: lineCaret.visible; loops: Animation.Infinite
                NumberAnimation { to: 0; duration: 530; easing.type: Easing.InOutCubic }
                NumberAnimation { to: 1; duration: 530; easing.type: Easing.InOutCubic }
            }
        }
        Rectangle {
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            width: height; height: parent.height - 12; radius: height / 2
            color: root.floodStep >= 0 ? Theme.inkText : Theme.ink
            opacity: root.count > 0 || root.floodStep >= 0 ? 1 : 0.45
            Behavior on opacity { NumberAnimation { duration: Theme.tQuick } }
            Icon { anchors.centerIn: parent; name: "right"; size: 16; stroke: 2.2; color: root.floodStep >= 0 ? Theme.ink : Theme.inkText }
        }
    }
}
