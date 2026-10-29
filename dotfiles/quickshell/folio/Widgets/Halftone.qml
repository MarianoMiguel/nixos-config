import QtQuick
import QtQuick.Window
import qs.Common

// A halftone screen: the kit's radial-gradient dots (1 px on a 3 px pitch) in
// ink over a background. Typed cells print with it (progress) and flood
// solid (solid); dialog scrims use it with the night shade.
ShaderEffect {
    id: root
    property color ink: Theme.ink
    property color back: "transparent"
    property real pitch: 3                  // logical pixels
    property real dotRadius: 1.05           // logical pixels
    property real progress: 1
    property real solid: 0
    property real seed: Math.floor(Math.random() * 97)

    readonly property real dpr: Screen.devicePixelRatio || 1
    property vector2d res: Qt.vector2d(Math.max(1, width * dpr), Math.max(1, height * dpr))
    property real radius: dotRadius * dpr
    property real pitchPx: pitch * dpr
    fragmentShader: Qt.resolvedUrl("../shaders/halftone.frag.qsb")
}
