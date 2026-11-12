import QtQuick
import qs.Common

// The kit's .card: a well with a hairline, its corner concentric with the
// sheet's (26 - 14 padding).
Rectangle {
    radius: Theme.inner(26, 14)
    color: Theme.well
    border.width: 1
    border.color: Theme.rule
}
