import QtQuick
import qs.Common

// One slot in the dock: the icon, the running dot and the press (sink, ink
// ring, two-hop bounce). The window drives s, the magnification; the slot
// grows upward out of the dock and pushes its neighbours aside.
Item {
    id: root
    property string key
    property string appId
    property string name
    property bool pinned: false
    property string icon
    property string glyph: ""
    property int running: 0
    property bool leaving: false
    property bool fresh: false
    property string mode: "original"
    property string shape: ""
    property var probe: null
    property real base: 50
    property real gap: 8
    property real corner: 0.3              // tile corner / icon size (the dock's concentric radius)
    property real s: 1
    property real appear: fresh ? 0 : 1
    readonly property real maxScale: 1.62
    readonly property real size: base * s
    readonly property bool hovered: hit.containsMouse
    readonly property bool pressed: hit.pressed
    signal activated(int button, point at)
    signal gone()

    width: (size + gap) * Math.max(0, appear)
    height: base

    // Arrivals spring in; departures shrink away, then leave the model.
    Component.onCompleted: if (fresh) appear = 1
    Behavior on appear { enabled: !root.leaving; SpringSoft {} }
    onLeavingChanged: {
        if (leaving) { outAnim.from = appear; outAnim.start(); }
        else { outAnim.stop(); appear = 1; }
    }
    Ease { id: outAnim; target: root; property: "appear"; to: 0; duration: Theme.tPanel; onFinished: root.gone() }

    property real press: hit.pressed ? 0.95 : 1
    Behavior on press { SpringPress {} }
    property real hop: 0

    function bounce() { hopAnim.restart(); }
    function stamp() { ringAnim.restart(); }
    SequentialAnimation {
        id: hopAnim
        NumberAnimation { target: root; property: "hop"; to: 22; duration: 190 * Theme.motion; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "hop"; to: 0; duration: 190 * Theme.motion; easing.type: Easing.InQuad }
        NumberAnimation { target: root; property: "hop"; to: 9; duration: 140 * Theme.motion; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "hop"; to: 0; duration: 140 * Theme.motion; easing.type: Easing.InQuad }
    }

    // Stamp: a ring of ink prints outward from the icon and dries.
    Rectangle {
        id: ring
        property real spread: 0
        visible: ringAnim.running
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.hop - spread
        width: root.size * root.press + spread * 2
        height: width
        radius: root.size * root.press * root.corner + spread
        color: "transparent"
        border.width: spread
        border.color: Theme.rgba(Theme.ink, 0.4 * (1 - spread / 14))
    }
    Ease { id: ringAnim; target: ring; property: "spread"; from: 0; to: 14; duration: 520 * Theme.motion }

    Item {
        id: box
        width: root.base * root.maxScale
        height: width
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.hop
        transformOrigin: Item.Bottom
        scale: root.s / root.maxScale * root.press * Math.min(1, Math.max(0, root.appear))
        DockIcon {
            anchors.fill: parent
            source: root.icon
            name: root.name
            glyph: root.glyph
            mode: root.mode
            shape: root.shape
            unit: root.maxScale
            corner: root.corner
            probe: root.probe
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.base + 3
        width: 4; height: 4; radius: 2
        color: Theme.ink
        opacity: root.running > 0 && !root.leaving ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.tQuick } }
    }

    // The whole slot answers, gaps included, so the tooltip never flickers.
    MouseArea {
        id: hit
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: parent.width
        height: root.size
        enabled: !root.leaving
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => root.activated(mouse.button, hit.mapToItem(null, mouse.x, mouse.y))
    }
}
