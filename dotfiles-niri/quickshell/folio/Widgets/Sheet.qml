import QtQuick
import QtQuick.Effects
import qs.Common

// Lifted paper: a translucent fill (frosted by niri's blur behind the window),
// a hairline edge, a top highlight and a soft night-tinted shadow.
Item {
    id: root
    property real radius: Theme.rL
    property color color: Theme.sheet
    property bool shadow: true
    property real elevation: 1
    default property alias content: inside.data

    RectangularShadow {
        anchors.fill: fill
        visible: root.shadow
        radius: root.radius
        blur: 26 * root.elevation
        spread: -2
        offset: Qt.vector2d(0, 8 * root.elevation)
        color: Theme.rgba(Theme.shade, Theme.dark ? 0.42 : 0.16)
    }
    Rectangle {
        id: fill
        anchors.fill: parent
        radius: root.radius
        color: root.color
        border.width: 1
        border.color: Theme.rule
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, root.radius - 1)
        color: "transparent"
        border.width: 1
        border.color: Theme.highlight
        opacity: 0.6
    }
    Item {
        id: inside
        anchors.fill: parent
    }
}
