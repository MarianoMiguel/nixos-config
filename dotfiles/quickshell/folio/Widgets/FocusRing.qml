import QtQuick
import qs.Common

// The keyboard's focus ring: two pixels of ink a small gap outside the
// control, its corner concentric with the control's (the control's radius
// plus the gap), so it reads as the control's own edge drawn again. It
// closes in on a spring when focus arrives from the keyboard and widens and
// fades the way it came when focus leaves; it never shows for the pointer
// (KeyNav.keyboard). Put it inside the control it rings:
//
//   FocusRing { radius: Theme.rS }
//
// `on` is what it follows (the parent's activeFocus by default). `inside`
// (or a negative gap) draws it within the control, `gap` in from its edge,
// for rows in a card where an outside ring would cross the neighbours; it
// stays concentric there too.
Item {
    id: root
    property bool on: !!parent && parent.activeFocus
    property real radius: 0
    property real gap: 3
    property bool inside: gap < 0
    property real thickness: 2
    property color color: Theme.ink
    readonly property bool shown: on && KeyNav.keyboard

    anchors.fill: parent
    z: 100

    // 0 hidden, 1 shown. Its overshoot pulls the ring a pixel in before it
    // settles, like a stamp finding the edge.
    property real t: shown ? 1 : 0
    Behavior on t { enabled: Theme.motion > 0.1; SpringPress {} }
    // From the control's edge to the ring's outer edge.
    readonly property real offset: (inside ? -Math.abs(gap) : gap + thickness) + 6 * (1 - t)

    Rectangle {
        visible: root.t > 0.01
        anchors.fill: parent
        anchors.margins: -root.offset
        radius: Math.max(0, root.radius + root.offset)
        color: "transparent"
        border.width: root.thickness
        border.color: root.color
        opacity: Math.max(0, Math.min(1, root.t))
    }
}
