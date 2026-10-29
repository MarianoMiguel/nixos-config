import QtQuick
import QtQuick.Layouts
import qs.Common

// A group of rows on the page's well: SettingRow, ListRow or anything with
// Layout.fillWidth. Rows are separated by hairlines when divided is set.
Rectangle {
    id: root
    default property alias rows: column.data
    property bool divided: false
    Layout.fillWidth: true
    implicitHeight: column.implicitHeight
    radius: Theme.rM
    color: Theme.well
    border.color: Theme.rule
    ColumnLayout {
        id: column
        width: parent.width
        spacing: 0
        onChildrenChanged: relayoutSoon.restart()
        onImplicitHeightChanged: relayoutSoon.restart()
    }
    // Hairlines above every visible row but the first, from where the layout
    // put them (rows from a Repeater included).
    property var lines: []
    function relayout() {
        lines = Array.prototype.filter.call(column.children, c => c.visible && c.height > 0)
            .sort((a, b) => a.y - b.y).slice(1).map(c => c.y);
    }
    Timer { id: relayoutSoon; interval: 0; onTriggered: root.relayout() }
    Repeater {
        model: root.divided ? root.lines : []
        Rectangle {
            required property real modelData
            x: 14; width: root.width - 28; height: 1
            y: modelData
            color: Theme.rule
        }
    }
}
