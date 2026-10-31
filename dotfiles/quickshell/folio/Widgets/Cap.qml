import QtQuick
import qs.Common

// The caption for anything that is metadata: Folio's book-plate mono
// capitals, Lumen's small sentence case (Theme.cap*).
Text {
    color: Theme.text3
    font.family: Theme.capFamily
    font.pixelSize: Theme.fsCap
    font.weight: Theme.capWeight
    font.letterSpacing: Theme.capSpacing
    font.capitalization: Theme.capCase
    elide: Text.ElideRight
    maximumLineCount: 1
    textFormat: Text.PlainText
}
