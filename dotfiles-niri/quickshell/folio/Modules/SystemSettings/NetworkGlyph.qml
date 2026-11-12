import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Widgets

// Glyphs the Network and Bluetooth pages need beyond the kit, drawn the kit's
// way (24-unit grid, 1.6 stroke, round caps): Wi-Fi in signal steps (name
// "wifi" with signal 0–100 lights that many arcs) and the device kinds the
// kit lacks (phone, gamepad, watch, printer). Any other name is the kit's Icon.
Item {
    id: root
    property string name
    property int signal: -1
    property color color: Theme.text
    property real size: 16
    implicitWidth: size
    implicitHeight: size

    readonly property var extra: ({
        "phone": ["M8.6,2.5h6.8a2.1,2.1 0 0 1 2.1,2.1v14.8a2.1,2.1 0 0 1 -2.1,2.1h-6.8a2.1,2.1 0 0 1 -2.1,-2.1v-14.8a2.1,2.1 0 0 1 2.1,-2.1z", "M11 18.4h2"],
        "gamepad": ["M7.6 7.5h8.8a5 5 0 0 1 4.9 6l-.7 3.5a2.2 2.2 0 0 1-3.8 1L15 16H9l-1.8 2a2.2 2.2 0 0 1-3.8-1l-.7-3.5a5 5 0 0 1 4.9-6z", "M8.5 10.3v3.4M6.8 12h3.4", "M15.6 11h.01M17.6 13h.01"],
        "watch": ["M8.5,7h7a2,2 0 0 1 2,2v6a2,2 0 0 1 -2,2h-7a2,2 0 0 1 -2,-2v-6a2,2 0 0 1 2,-2z", "M9 7l.8-3.5h4.4L15 7M9 17l.8 3.5h4.4L15 17", "M12 10v2.2l1.4 1"],
        "printer": ["M7 9V3.5h10V9", "M7 17H5a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2h-2", "M7 14h10v6.5H7z"]
    })
    readonly property var arcs: ["M2.5 9a14 14 0 0 1 19 0", "M5.5 12.5a9.5 9.5 0 0 1 13 0", "M8.5 16a5 5 0 0 1 7 0"]
    readonly property bool stepped: name === "wifi" && signal >= 0
    readonly property int lit: signal >= 70 ? 3 : signal >= 45 ? 2 : signal >= 20 ? 1 : 0

    Icon { anchors.fill: parent; visible: !root.stepped && !root.extra[root.name]; name: root.name; size: root.size; color: root.color }

    // Extra kinds, and the Wi-Fi arcs (unlit ones faint).
    Repeater {
        model: root.stepped ? root.arcs.map((d, i) => ({ "d": d, "on": 2 - i < root.lit }))
             : (root.extra[root.name] || []).map(d => ({ "d": d, "on": true }))
        Shape {
            required property var modelData
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: Qt.size(root.width / 24, root.height / 24)
                strokeColor: modelData.on ? root.color : Theme.rgba(root.color, 0.28)
                strokeWidth: 1.6
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: modelData.d }
            }
        }
    }
    Rectangle {
        visible: root.stepped
        width: root.size * 2.4 / 24; height: width; radius: width / 2
        x: root.size * 10.8 / 24; y: root.size * 18.1 / 24
        color: root.color
    }
}
