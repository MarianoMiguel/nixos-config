import QtQuick
import qs.Common

// Interface text. Never wraps or overflows by accident: set elide or wrap
// on purpose (names elide; bodies use maximumLineCount).
Text {
    color: Theme.text
    font.family: Theme.ui
    font.pixelSize: Theme.fsM
    elide: Text.ElideRight
    maximumLineCount: 1
    textFormat: Text.PlainText
    verticalAlignment: Text.AlignVCenter
}
