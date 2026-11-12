import QtQuick

// Makes a blur region stick. niri 26.04 sometimes drops a blur region that
// arrives while the surface keeps redrawing (Folio's panels animate as they
// open), which leaves no frost behind a panel, or a stale patch after one
// closes. Sending the region again makes it stick, so after every change of
// `key`, and once at start, the region's corners grow by `extra` (one pixel)
// and come back a few times in quick succession; each send either lands or
// the next one does, and the final shape is unchanged.
//
//   BlurNudge { id: frost; key: root.open }
//   BackgroundEffect.blurRegion: Region { item: sheet; radius: 26 + frost.extra }
QtObject {
    id: root
    property var key
    property int extra: 0
    // Gaps between re-sends, in ms: early ones so a dropped region costs
    // little, a late one for a surface that is still animating.
    property var steps: [120, 180, 250, 400, 700, 1200]
    property int step: 0

    function kick() { step = 0; extra = 0; timer.interval = steps[0]; timer.restart(); }
    onKeyChanged: kick()
    Component.onCompleted: kick()

    property Timer timer: Timer {
        onTriggered: {
            root.extra = 1 - root.extra;
            if (++root.step < root.steps.length) { interval = root.steps[root.step]; restart(); }
            else root.extra = 0;
        }
    }
}
