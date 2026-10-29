import QtQuick
import QtQuick.Shapes
import qs.Common

// A Folio icon (Common/Icons.qml, generated from the kit) drawn as vector
// shapes on the kit's 24-unit grid: 1.6 stroke, round caps and joins.
Item {
    id: root
    property string name
    property color color: Theme.text
    property real size: 18
    property real stroke: 1.6
    implicitWidth: size
    implicitHeight: size

    Repeater {
        model: Icons.get(root.name)
        Shape {
            required property var modelData
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: Qt.size(root.width / 24, root.height / 24)
                strokeColor: modelData.stroke ? root.color : "transparent"
                strokeWidth: modelData.stroke ? (modelData.w || root.stroke) : -1
                fillColor: modelData.fill ? root.color : "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: modelData.d }
            }
        }
    }
}
