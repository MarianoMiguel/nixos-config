import QtQuick
import QtQuick.Shapes
import qs.Common

// Interstellar's mark: a planet and its ring, drawn in one color at any size
// (the same drawing as workshop/studies/interstellar/v1.html).
Item {
    id: root
    property color color: Theme.text
    // Stroke as a share of the size; the study draws 2.4 on 48.
    property real weight: 0.07
    implicitWidth: 20
    implicitHeight: 20

    readonly property real s: Math.min(width, height)
    readonly property real stroke: Math.max(1.2, s * weight)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color; strokeWidth: root.stroke; fillColor: "transparent"
            PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.s * 0.21; radiusY: root.s * 0.21; startAngle: 0; sweepAngle: 360 }
        }
    }
    Shape {
        anchors.fill: parent
        rotation: -22
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color; strokeWidth: root.stroke; fillColor: "transparent"
            PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.s * 0.44; radiusY: root.s * 0.15; startAngle: 0; sweepAngle: 360 }
        }
    }
}
