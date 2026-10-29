import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// Elapsed, a thin track, remaining. Click or drag to seek; between the
// player's once-a-second updates the fill glides on.
RowLayout {
    id: root

    property var hub
    readonly property real length: hub ? hub.length : 0
    property real shown: hub ? hub.position : 0
    property real drag: -1                  // seconds under the pointer while dragging
    readonly property real at: drag >= 0 ? drag : shown
    readonly property real frac: length > 0 ? Math.max(0, Math.min(1, at / length)) : 0
    spacing: 10

    // Small steps glide; jumps (seeks, new tracks) land at once.
    Connections {
        target: root.hub
        function onPositionChanged() {
            const p = root.hub.position;
            glide.stop();
            if (root.hub.playing && p > root.shown && p - root.shown < 2) { glide.to = p; glide.restart(); }
            else root.shown = p;
        }
    }
    NumberAnimation { id: glide; target: root; property: "shown"; duration: 1000 }

    function clock(s) {
        s = Math.max(0, Math.floor(s));
        const m = Math.floor(s / 60) % 60, ss = String(s % 60).padStart(2, "0");
        return s >= 3600 ? Math.floor(s / 3600) + ":" + String(m).padStart(2, "0") + ":" + ss : m + ":" + ss;
    }

    Label {
        text: root.clock(root.at)
        color: Theme.islandText
        opacity: 0.85
        font.family: Theme.mono
        font.pixelSize: 11
    }
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 14
        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: area.containsMouse || area.pressed ? 6 : 4
            Behavior on height { SpringPress {} }
            radius: height / 2
            color: Theme.rgba(Theme.islandText, 0.16)
            Rectangle {
                width: Math.max(height, parent.width * root.frac)
                height: parent.height
                radius: parent.radius
                color: Theme.islandText
                visible: root.length > 0
            }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            anchors.topMargin: -4; anchors.bottomMargin: -4
            enabled: root.length > 0
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            function at(x) { return Math.max(0, Math.min(1, x / width)) * root.length; }
            onPressed: mouse => root.drag = at(mouse.x)
            onPositionChanged: mouse => { if (pressed) root.drag = at(mouse.x); }
            onReleased: mouse => { root.hub.seek(at(mouse.x)); root.shown = at(mouse.x); root.drag = -1; }
            onCanceled: root.drag = -1
        }
    }
    Label {
        text: root.length > 0 ? "−" + root.clock(root.length - root.at) : "−:−"
        color: Theme.islandText
        opacity: 0.85
        font.family: Theme.mono
        font.pixelSize: 11
    }
}
