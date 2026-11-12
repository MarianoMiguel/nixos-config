import QtQuick
import qs.Common

// Text that prints its new value instead of swapping it: the old characters
// lift as the new ones print, dot for dot (a clock's new minute).
Item {
    id: root
    property string text
    property font font
    property color color: Theme.text
    property real lineHeight: 1
    property int duration: 600
    implicitWidth: now.implicitWidth
    implicitHeight: now.implicitHeight

    property string shown: ""
    property string old: ""
    onTextChanged: {
        if (!shown) { shown = text; return; }
        old = shown;
        shown = text;
        incoming.run(0, 1, duration);
    }
    Component.onCompleted: shown = text

    Develop {
        anchors.fill: parent
        visible: incoming.running
        invert: true
        progress: incoming.progress
        seed: incoming.seed
        grain: incoming.grain
        Text {
            text: root.old; font: root.font; color: root.color
            lineHeight: root.lineHeight; lineHeightMode: Text.ProportionalHeight
        }
    }
    Develop {
        id: incoming
        anchors.fill: parent
        Text {
            id: now
            text: root.shown; font: root.font; color: root.color
            lineHeight: root.lineHeight; lineHeightMode: Text.ProportionalHeight
        }
    }
}
