import QtQuick
import QtQuick.Layouts
import qs.Common

// An inline list that opens under a row (profiles, where an app plays): its
// height follows the content on a spring, so a reversal mid-way stays smooth.
Item {
    id: root
    property bool open: false
    default property alias content: inner.data
    Layout.fillWidth: true
    clip: true
    implicitHeight: open ? inner.implicitHeight : 0
    Behavior on implicitHeight { SpringPanel {} }
    visible: implicitHeight > 0.5
    ColumnLayout { id: inner; width: parent.width; spacing: 0 }
}
