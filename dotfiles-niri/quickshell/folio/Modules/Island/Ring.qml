import QtQuick
import QtQuick.Shapes
import qs.Common

// A progress ring: a faint track and an ink arc from twelve o'clock.
Item {
    id: root

    property real progress: 0
    property color track: Theme.rgba(Theme.islandText, 0.18)
    property color color: Theme.islandInk
    property real stroke: 1.9
    implicitWidth: 16
    implicitHeight: 16
    Behavior on progress { NumberAnimation { duration: 1000 } }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.track
            strokeWidth: root.stroke
            fillColor: "transparent"
            PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.width * 0.375; radiusY: root.height * 0.375; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.stroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.width * 0.375; radiusY: root.height * 0.375; startAngle: -90; sweepAngle: 360 * Math.max(0.001, Math.min(1, root.progress)) }
        }
    }
}
