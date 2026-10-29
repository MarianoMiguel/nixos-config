import QtQuick
import QtQuick.Effects
import qs.Common

// One line that glides back and forth only when it overflows, at reading
// pace, pausing at each end, with faded edges. Otherwise plain text.
Item {
    id: root
    property alias text: label.text
    property alias font: label.font
    property alias color: label.color
    readonly property real overflow: Math.max(0, label.implicitWidth - width)
    implicitHeight: label.implicitHeight
    clip: true

    Item {
        id: strip
        anchors.fill: parent
        layer.enabled: root.overflow > 1
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: fadeMask
            maskThresholdMin: 0.0
            maskSpreadAtMin: 1.0
        }
        Label {
            id: label
            elide: Text.ElideNone
            anchors.verticalCenter: parent.verticalCenter
            x: 0
            SequentialAnimation on x {
                running: root.overflow > 1 && root.visible
                loops: Animation.Infinite
                PauseAnimation { duration: 1800 }
                NumberAnimation { to: -root.overflow - 8; duration: Math.max(2500, (root.overflow + 8) * 36); easing.type: Easing.InOutSine }
                PauseAnimation { duration: 1800 }
                NumberAnimation { to: 0; duration: Math.max(2500, (root.overflow + 8) * 36); easing.type: Easing.InOutSine }
                onStopped: label.x = 0
            }
        }
    }
    Item {
        id: fadeMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: label.x < -1 ? "transparent" : "white" }
                GradientStop { position: Math.min(0.5, 14 / Math.max(1, root.width)); color: "white" }
                GradientStop { position: 1 - Math.min(0.5, 22 / Math.max(1, root.width)); color: "white" }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }
}
