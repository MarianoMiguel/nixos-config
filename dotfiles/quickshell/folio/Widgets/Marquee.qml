import QtQuick
import QtQuick.Effects
import QtQuick.Window
import qs.Common
import qs.Services

// One line that glides back and forth only when it overflows, at reading
// pace, pausing at each end, with faded edges. Otherwise plain text. It
// glides only where it can be seen: in a window that is showing (a closed
// sidebar keeps its items "visible") and not while nobody could see it
// (desktop text under the lock; the lock's own sets unseen to
// Unseen.screensOff). Stopped, it rests at its start.
Item {
    id: root
    property alias text: label.text
    property alias font: label.font
    property alias color: label.color
    property bool unseen: Unseen.desktop
    readonly property real overflow: Math.max(0, label.implicitWidth - width)
    readonly property bool seen: visible && Window.visibility !== Window.Hidden && !unseen
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
                running: root.overflow > 1 && root.seen
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
