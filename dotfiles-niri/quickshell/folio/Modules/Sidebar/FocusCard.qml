import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.Common
import qs.Widgets

// A focus session: the ring empties as time runs, the count, and Start or
// Stop. While it runs, notifications wait.
SideCard {
    id: root
    required property var feed

    implicitHeight: 92

    RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 14

        Shape {
            id: ring
            implicitWidth: 64
            implicitHeight: 64
            preferredRendererType: Shape.CurveRenderer
            property real progress: root.feed.focusProgress
            Behavior on progress { NumberAnimation { duration: 1000 } }
            ShapePath {
                strokeColor: Theme.wellStrong
                strokeWidth: 5
                fillColor: "transparent"
                PathAngleArc { centerX: 32; centerY: 32; radiusX: 26; radiusY: 26; startAngle: 0; sweepAngle: 360 }
            }
            // A fresh session shows no arc at all.
            ShapePath {
                strokeColor: ring.progress > 0.002 ? Theme.ink : "transparent"
                strokeWidth: 5
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: 32; centerY: 32; radiusX: 26; radiusY: 26; startAngle: -90; sweepAngle: 360 * Math.max(0.001, ring.progress) }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 4
            Text {
                text: root.feed.focusClock
                color: Theme.text
                font.family: Theme.ui
                font.pixelSize: Theme.fsXl
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
            }
            Text {
                text: root.feed.focusActive ? "Until " + Qt.formatTime(new Date(root.feed.focusEnds), "HH:mm") + " · notifications wait" : "Deep work · silences notifications"
                color: Theme.text2
                font.family: Theme.ui
                font.pixelSize: Theme.fsS - 1
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }
        }
        SideButton {
            kind: "ink"
            text: root.feed.focusActive ? "Stop" : "Start"
            onClicked: root.feed.toggleFocus()
        }
    }
}
