import QtQuick

// Pointer use over a Folio surface. When the pointer really moves (not when
// the surface moves or opens under a still pointer), focus rings go until the
// next key (KeyNav.pointer()). Put one in each window's root item; it only
// watches, so hover and clicks still reach everything under it.
HoverHandler {
    id: root
    property point last: Qt.point(-1e6, -1e6)
    signal moved()
    onHoveredChanged: if (!hovered) last = Qt.point(-1e6, -1e6)
    onPointChanged: {
        const p = point.scenePosition;
        const fresh = last.x < -1e5;
        const far = Math.abs(p.x - last.x) + Math.abs(p.y - last.y) > 3;
        last = p;
        if (!fresh && far) { KeyNav.pointer(); root.moved(); }
    }
}
