import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// AI usage limits, one row per window: twenty segments that turn to the
// warning tone at 60% and to the error tone at the limit, and when the
// window resets.
SideCard {
    id: root
    required property var feed

    implicitHeight: col.implicitHeight + 24

    // The widest "Limit · resets Mon", so every meter ends at the same x.
    Column {
        id: tails
        visible: false
        Repeater {
            model: root.feed.quota
            Text {
                required property var modelData
                text: root.tail(modelData)
                font.family: Theme.mono
                font.pixelSize: Theme.fsCap + 0.5
                font.weight: Font.Medium
            }
        }
    }
    function tail(q) {
        const reset = q.used === 0 && !q.resetsAt ? "unused" : Quota.resetLabel(q.resetsAt, feed.now);
        return (q.used >= 1 ? "Limit" : Math.round(q.used * 100) + "%") + (reset ? " · " + reset : "");
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 14; topMargin: 12 }
        spacing: 10

        Repeater {
            model: root.feed.quota
            RowLayout {
                id: row
                required property var modelData
                readonly property real used: modelData.used
                readonly property color tone: used >= 1 ? Theme.error : used >= 0.6 ? Theme.warning : Theme.ink
                Layout.fillWidth: true
                spacing: 10

                Row {
                    Layout.preferredWidth: 84
                    Layout.maximumWidth: 84
                    spacing: 5
                    clip: true
                    Label { id: who; text: row.modelData.name; font.pixelSize: Theme.fsS; font.weight: Font.DemiBold; width: Math.min(implicitWidth, 84 - win.implicitWidth - 5); anchors.baseline: win.baseline }
                    Cap { id: win; text: row.modelData.window }
                }
                ClippingRectangle {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 40
                    implicitHeight: 8
                    radius: 4
                    color: Theme.wellStrong
                    Row {
                        id: segs
                        anchors.fill: parent
                        spacing: 2
                        Repeater {
                            model: 20
                            Rectangle {
                                required property int index
                                width: (segs.width - 38) / 20
                                height: segs.height
                                readonly property bool on: index < Math.round(Math.min(1, row.used) * 20)
                                color: on ? row.tone : Theme.ink
                                opacity: on ? 1 : 0.15
                            }
                        }
                    }
                }
                Text {
                    Layout.preferredWidth: tails.implicitWidth
                    horizontalAlignment: Text.AlignRight
                    text: root.tail(row.modelData)
                    color: row.used >= 1 ? Theme.error : Theme.text2
                    font.family: Theme.mono
                    font.pixelSize: Theme.fsCap + 0.5
                    font.weight: Font.Medium
                }
            }
        }
    }
}
