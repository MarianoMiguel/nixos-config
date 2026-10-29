import QtQuick
import qs.Common

// A pressable surface with the kit's stamp: it sinks on a spring while
// pressed and prints a ring of ink outward that dries. The click area sits
// under the content, so nested controls still take their own clicks.
Item {
    id: root

    property real radius: Theme.rS
    property bool stamp: true
    property bool sink: true
    readonly property alias hovered: area.containsMouse
    readonly property alias pressed: area.pressed
    signal clicked()
    default property alias content: inner.data

    scale: sink && area.pressed ? 0.95 : 1
    Behavior on scale { SpringPress {} }

    Rectangle {
        id: ring
        property real t: 1
        visible: t < 1
        anchors.fill: parent
        anchors.margins: -14 * t
        radius: root.radius + 14 * t
        color: "transparent"
        border.width: 14 * t
        border.color: Theme.rgba(Theme.ink, 0.4 * (1 - t))
        NumberAnimation {
            id: stampAnim
            target: ring; property: "t"; from: 0; to: 1; duration: Theme.tPage
            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: if (root.stamp) stampAnim.restart()
        onClicked: root.clicked()
    }
    Item {
        id: inner
        anchors.fill: parent
    }
}
