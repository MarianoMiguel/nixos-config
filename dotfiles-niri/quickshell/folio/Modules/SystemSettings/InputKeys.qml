import QtQuick
import qs.Common
import qs.Widgets

// Keycaps for a shortcut ("Super", "Shift", "T"): mono caps on a sheet with a
// pressed-in lower edge, as in the controls study.
Row {
    id: root
    property var caps: []
    property bool inverted: false       // on an ink fill
    spacing: 3

    Repeater {
        model: root.caps
        Item {
            required property string modelData
            width: Math.max(20, cap.implicitWidth + 12)
            height: 21
            Rectangle {
                y: 1.5; width: parent.width; height: parent.height - 1.5; radius: Theme.rXs
                color: root.inverted ? "transparent" : Theme.ruleStrong
            }
            Rectangle {
                width: parent.width; height: parent.height - 1.5; radius: Theme.rXs
                color: root.inverted ? "transparent" : Theme.sheetStrong
                border.width: 1
                border.color: root.inverted ? Theme.inkText : Theme.ruleStrong
                Text {
                    id: cap
                    anchors.centerIn: parent
                    text: modelData
                    font.family: Theme.mono; font.pixelSize: Theme.fsCap; font.weight: Font.Medium; font.letterSpacing: 0.4
                    color: root.inverted ? Theme.inkText : Theme.text2
                    textFormat: Text.PlainText
                }
            }
        }
    }
}
