import QtQuick
import qs.Common

// The book-plate caption: mono capitals for anything that is metadata.
Text {
    color: Theme.text3
    font.family: Theme.mono
    font.pixelSize: Theme.fsCap
    font.weight: Font.Medium
    font.letterSpacing: 1.2
    font.capitalization: Font.AllUppercase
    elide: Text.ElideRight
    maximumLineCount: 1
    textFormat: Text.PlainText
}
