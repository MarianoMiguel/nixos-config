import QtQuick
import qs.Common
import qs.Widgets

// A slider with its two ends named under it ("Slow", "Fast"), for settings
// that are a feel rather than a number.
Item {
    id: root
    property real value: 0
    property real to: 1
    property real step: 0.05
    property string low
    property string high
    signal moved(real v)
    implicitWidth: 240
    implicitHeight: 40

    Slider { id: slider; width: parent.width; value: root.value; to: root.to; step: root.step; onMoved: v => root.moved(v) }
    Cap { x: 8; y: 26; text: root.low; font.letterSpacing: 0.8 }
    Cap { anchors.right: parent.right; anchors.rightMargin: 8; y: 26; text: root.high; font.letterSpacing: 0.8 }
}
