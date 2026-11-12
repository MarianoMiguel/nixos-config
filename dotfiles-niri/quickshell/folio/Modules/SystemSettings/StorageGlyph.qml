import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Widgets

// The Trash, drawn like the kit's icons (24-unit grid, 1.6 stroke, round
// caps and joins) until the kit has a `trash` icon; then that one.
Item {
    id: root
    property color color: Theme.text
    property real size: 16
    readonly property bool kit: Icons.get("trash").length > 0
    implicitWidth: size
    implicitHeight: size

    Icon { visible: root.kit; anchors.fill: parent; name: "trash"; size: root.size; color: root.color }
    Shape {
        visible: !root.kit
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            scale: Qt.size(root.width / 24, root.height / 24)
            strokeColor: root.color
            strokeWidth: 1.6
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M4.5 7h15M9.5 7V5.2a1.2 1.2 0 0 1 1.2-1.2h2.6a1.2 1.2 0 0 1 1.2 1.2V7M6.5 7l.9 11.6a1.8 1.8 0 0 0 1.8 1.6h5.6a1.8 1.8 0 0 0 1.8-1.6L17.5 7M10.2 11v5.4M13.8 11v5.4" }
        }
    }
}
