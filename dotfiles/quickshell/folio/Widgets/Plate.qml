import QtQuick
import QtQuick.Window
import qs.Common
import qs.Services

// A Folio plate printed live by shaders/plate.frag. It develops the first
// time, dissolves dot by dot to a new plate, bleeds new colors in from a
// point, keeps its dither moving (breathe) and prints moonlit in dark mode.
ShaderEffect {
    id: root

    property string plate: Art.current
    property real breathe: 0
    property real lift: 0
    property real dot: 1                    // logical pixels per dot
    property real zoom: 1
    property string forceMode: ""          // pin a preview to light or dark
    property bool developOnLoad: true
    property bool portrait: false
    property int textureWidth: 0            // downscale the source for thumbnails (0 = full)

    // Uniforms
    readonly property real dpr: Screen.devicePixelRatio || 1
    property vector2d res: Qt.vector2d(Math.max(1, width * dpr), Math.max(1, height * dpr))
    property vector2d focusA: Art.focus(front ? frontId : backId)
    property vector2d focusB: Art.focus(front ? backId : frontId)
    property vector2d origin: Qt.vector2d(res.x / 2, res.y / 2)
    property color paper0: "#f7f4e9"
    property color ink0: "#214c94"
    property color paper1: "#f7f4e9"
    property color ink1: "#214c94"
    property real dotSize: Math.max(1, Math.round(dot * dpr))
    property real mixAB: 0
    property real develop: developOnLoad ? 0 : 1
    property real radius: 1e7
    property real edge: 90 * dpr
    property real time: 0
    property real zoomA: zoom
    property real zoomB: zoom
    property real invert0: 0
    property real invert1: 0
    property real thin0: 0
    property real thin1: 0
    property var sourceA: front ? imgFront : imgBack
    property var sourceB: front ? imgBack : imgFront

    fragmentShader: Qt.resolvedUrl("../shaders/plate.frag.qsb")
    blending: false

    // Two images swap roles, so a dissolve never reloads a texture mid-way.
    property bool front: true
    property string frontId: ""
    property string backId: ""
    Image { id: imgFront; visible: false; asynchronous: true; smooth: true; sourceSize.width: root.textureWidth; source: root.portrait ? Art.portrait(root.frontId) : Art.mask(root.frontId) }
    Image { id: imgBack; visible: false; asynchronous: true; smooth: true; sourceSize.width: root.textureWidth; source: root.portrait ? Art.portrait(root.backId) : Art.mask(root.backId) }
    readonly property bool ready: (front ? imgFront : imgBack).status === Image.Ready

    function palette() {
        const mode = root.forceMode || Theme.mode;
        const ink = Theme.inks[Theme.inkName] || Theme.inks.azure;
        if (mode !== "dark")
            return { "paper": "#f7f4e9", "ink": ink[0], "invert": 0, "thin": 0 };
        if (Settings.get("plates.dark") === "negative")
            return { "paper": "#101d33", "ink": ink[1], "invert": 0, "thin": 0 };
        return { "paper": "#101d33", "ink": Theme.mix(Qt.color(ink[1]), Qt.color("#101d33"), 0.22), "invert": 1, "thin": 0.2 };
    }
    property var target: palette()
    onTargetChanged: bleedFrom(origin.x / dpr, origin.y / dpr)

    // Bleed new colors in from (x, y), in item coordinates.
    function bleedFrom(x, y) {
        const t = root.target;
        root.paper1 = t.paper; root.ink1 = t.ink; root.invert1 = t.invert; root.thin1 = t.thin;
        root.origin = Qt.vector2d(x * dpr, y * dpr);
        const far = Math.max(Math.hypot(x, y), Math.hypot(width - x, y), Math.hypot(x, height - y), Math.hypot(width - x, height - y)) * dpr;
        bleedAnim.stop();
        bleedAnim.to = far + edge;
        root.radius = -edge;
        bleedAnim.start();
    }
    NumberAnimation {
        id: bleedAnim
        target: root; property: "radius"; duration: 950
        easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
        onFinished: {
            root.paper0 = root.paper1; root.ink0 = root.ink1; root.invert0 = root.invert1; root.thin0 = root.thin1;
            root.radius = 1e7;
        }
    }

    function redevelop(ms) {
        developAnim.duration = ms || 1400;
        developAnim.from = 0;
        developAnim.restart();
    }
    NumberAnimation {
        id: developAnim
        target: root; property: "develop"; from: 0; to: 1; duration: 1400
        easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1]
    }

    onPlateChanged: show(plate)
    function show(id) {
        if (!id) return;
        if (!frontId) { frontId = id; return; }
        if (id === (front ? frontId : backId)) return;
        if (front) backId = id; else frontId = id;
        dissolveWait.restart();
    }
    // Wait for the incoming texture, then dissolve and swap roles.
    Timer {
        id: dissolveWait
        interval: 30; repeat: true
        onTriggered: {
            const incoming = root.front ? imgBack : imgFront;
            if (incoming.status === Image.Ready) { stop(); dissolveAnim.restart(); }
        }
    }
    NumberAnimation {
        id: dissolveAnim
        target: root; property: "mixAB"; from: 0; to: 1; duration: 1200
        easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1]
        onFinished: { root.front = !root.front; root.mixAB = 0; }
    }

    // The moving dither changes nine times a second; render only then.
    Timer {
        interval: 111; repeat: true
        running: root.breathe > 0 && root.visible
        onTriggered: root.time += 0.111
    }

    Component.onCompleted: {
        const t = palette();
        paper0 = paper1 = t.paper; ink0 = ink1 = t.ink; invert0 = invert1 = t.invert; thin0 = thin1 = t.thin;
        frontId = plate;
    }
    onReadyChanged: if (ready && developOnLoad && develop === 0) developAnim.start()
}
