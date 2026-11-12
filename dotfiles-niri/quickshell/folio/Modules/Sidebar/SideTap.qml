import QtQuick
import qs.Common
import qs.Widgets

// A pressable surface with the kit's stamp: it sinks on a spring while
// pressed and prints a ring of ink outward that dries. The click area sits
// under the content, so nested controls still take their own clicks.
// It takes keyboard focus (Tab, or the sidebar's arrows): Space or Enter
// press it, with the same stamp. Its focus ring sits outside a tile or a
// button and inside a row (`ringInside`, rows that do not sink); `ring`
// false leaves the focus mark to the owner (a menu's highlight).
Item {
    id: root

    property real radius: Theme.rS
    property bool stamp: true
    property bool sink: true
    property bool ring: true
    property bool ringInside: !sink
    readonly property alias hovered: area.containsMouse
    readonly property alias pressed: area.pressed
    signal clicked()
    default property alias content: inner.data

    scale: sink && (area.pressed || keyDown.running) ? 0.95 : 1
    Behavior on scale { SpringPress {} }

    activeFocusOnTab: true
    Keys.onPressed: event => KeyNav.press(event, () => {
        if (root.stamp) stampAnim.restart();
        keyDown.restart();
        root.clicked();
    })
    Timer { id: keyDown; interval: 110 }

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
    FocusRing { on: root.ring && root.activeFocus; radius: root.radius; inside: root.ringInside; gap: root.ringInside ? 0 : 3 }
}
