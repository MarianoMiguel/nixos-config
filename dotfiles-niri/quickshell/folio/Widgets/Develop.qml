import QtQuick
import QtQuick.Window
import qs.Common

// Prints its content in dot by dot (progress 0 -> 1) or lifts it off (1 -> 0),
// the plates' develop for interface items (shaders/develop.frag). Plain
// rendering when fully printed. Themes that do not print (Lumen) fade it
// instead, on the same progress. printIn(ms) and lift(ms) run the threshold
// linearly, as the kit does; finished() fires at the end.
Item {
    id: root
    property real progress: 1
    property real grain: 1                  // logical pixels per dot
    property bool invert: false             // show the dots not yet printed
    property real seed: Math.floor(Math.random() * 97)
    default property alias content: inner.data
    readonly property bool running: anim.running
    signal finished()

    function printIn(ms) { run(0, 1, ms === undefined ? Theme.tDevelop : ms); }
    function lift(ms) { run(progress, 0, ms === undefined ? 260 : ms); }
    function run(from, to, ms) {
        anim.stop();
        anim.from = from;
        anim.to = to;
        anim.duration = Math.max(1, ms * Theme.motion);
        anim.start();
    }
    NumberAnimation { id: anim; target: root; property: "progress"; onFinished: root.finished() }

    readonly property real dpr: Screen.devicePixelRatio || 1
    Item {
        id: inner
        anchors.fill: parent
        visible: root.invert ? root.progress < 1 : root.progress > 0
        opacity: Theme.prints ? 1 : (root.invert ? 1 - root.progress : root.progress)
        layer.enabled: Theme.prints && (root.invert ? root.progress > 0 : root.progress < 1)
        layer.effect: ShaderEffect {
            property vector2d res: Qt.vector2d(Math.max(1, inner.width * root.dpr), Math.max(1, inner.height * root.dpr))
            property real progress: root.progress
            property real dotSize: Math.max(1, Math.round(root.grain * root.dpr))
            property real seed: root.seed
            property real invert: root.invert ? 1 : 0
            fragmentShader: Qt.resolvedUrl("../shaders/develop.frag.qsb")
        }
    }
}
