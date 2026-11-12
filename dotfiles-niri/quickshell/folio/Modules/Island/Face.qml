import QtQuick
import qs.Common

// One of the island's faces, laid out at its own size in the pill's middle.
// It fades out at once and fades in once the pill has mostly grown, so the
// content never squeezes; leaving mirrors arriving.
Item {
    id: root

    property bool on: false
    anchors.centerIn: parent
    opacity: 0
    visible: opacity > 0.001
    enabled: on

    function settle() {
        fadeIn.stop(); fadeOut.stop();
        if (on) fadeIn.restart(); else fadeOut.restart();
    }
    onOnChanged: settle()
    Component.onCompleted: opacity = on ? 1 : 0

    SequentialAnimation {
        id: fadeIn
        PauseAnimation { duration: Math.round(120 * Theme.motion) }
        Ease { target: root; property: "opacity"; to: 1; duration: Math.round(220 * Theme.motion) }
    }
    Ease { id: fadeOut; target: root; property: "opacity"; to: 0; duration: Math.round(140 * Theme.motion) }
}
