import QtQuick

// Makes a blur region stick. niri 26.04 sometimes drops a blur region that
// arrives while the surface keeps redrawing (Folio's panels animate as they
// open), which leaves no frost behind a panel, or a stale patch after one
// closes. Sending the region again a moment later makes it stick: after every
// change of `key`, and once at start, the region's corners grow by `extra`
// (one pixel) for a moment and come back, so the final shape is unchanged.
//
//   BlurNudge { id: frost; key: root.settled }
//   BackgroundEffect.blurRegion: Region { item: sheet; radius: 26 + frost.extra }
QtObject {
    id: root
    property var key
    property int extra: 0

    onKeyChanged: first.restart()
    Component.onCompleted: first.restart()

    property Timer first: Timer { interval: 400; onTriggered: { root.extra = 1; second.restart(); } }
    property Timer second: Timer { interval: 300; onTriggered: root.extra = 0 }
}
