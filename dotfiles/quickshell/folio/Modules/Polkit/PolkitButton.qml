import QtQuick
import qs.Common
import qs.Widgets

// The kit's .btn: a well with a hairline, or solid ink. It sinks when pressed
// and prints a ring of ink that spreads and dries (stamp).
Item {
    id: root
    property string text
    property bool ink: false
    property real stamp: 1
    signal clicked()
    implicitWidth: label.implicitWidth + 28
    implicitHeight: 34

    Rectangle {
        anchors.fill: face
        anchors.margins: -14 * root.stamp
        radius: Theme.rS + 14 * root.stamp
        color: Theme.rgba(Theme.ink, 0.4 * (1 - root.stamp))
        visible: root.stamp < 1
    }
    Rectangle {
        id: face
        anchors.fill: parent
        radius: Theme.rS
        color: root.ink ? Theme.ink : area.containsMouse ? Theme.wellStrong : Theme.well
        border.width: root.ink ? 0 : 1
        border.color: Theme.rule
        scale: area.pressed ? 0.95 : 1
        Behavior on scale { SpringPress {} }
        Label {
            id: label
            anchors.centerIn: parent
            text: root.text
            color: root.ink ? Theme.inkText : Theme.text
            font.weight: Font.Medium
        }
    }
    NumberAnimation {
        id: grow
        target: root; property: "stamp"; from: 0; to: 1; duration: 520
        easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onPressed: grow.restart()
        onClicked: root.clicked()
    }
}
