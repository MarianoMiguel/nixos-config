import QtQuick
import qs.Common

// A key cap (controls study): mono, lifted by a hairline under it. On ink it
// turns into an outline in the ink's paper color.
Item {
    id: root
    property string text
    property bool inverted: false
    implicitWidth: Math.max(implicitHeight, label.implicitWidth + 12)
    implicitHeight: 19

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 1.5
        radius: Theme.rXs
        color: Theme.ruleStrong
        visible: !root.inverted
    }
    Rectangle {
        anchors.fill: parent
        anchors.bottomMargin: root.inverted ? 0 : 1.5
        radius: Theme.rXs
        color: root.inverted ? "transparent" : Theme.sheetStrong
        border.width: 1
        border.color: root.inverted ? Theme.rgba(Theme.paper, 0.55) : Theme.ruleStrong
        Text {
            id: label
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 0.5
            text: root.text
            color: root.inverted ? Theme.paper : Theme.text2
            // Plex Mono has no ↵ or ⌃; symbols set in Inter.
            font.family: /^[\u2190-\u23ff]+$/.test(root.text) ? Theme.ui : Theme.mono
            font.pixelSize: Theme.fsCap
            font.weight: Font.Medium
            font.letterSpacing: 0.4
            textFormat: Text.PlainText
        }
    }
}
