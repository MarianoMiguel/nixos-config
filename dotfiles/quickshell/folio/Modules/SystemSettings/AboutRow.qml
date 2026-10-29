import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// A fact in a Card (About, Power & battery): its name on the left, the value
// on the right, an optional line under the value. Both elide; anything put
// inside (a meter) sits under the value, right-aligned.
Item {
    id: root
    property string label
    property string value
    property string hint
    property color valueColor: Theme.text
    property real labelWidth: 150
    property bool showExtra: true
    default property alias extra: under.data
    Layout.fillWidth: true
    implicitHeight: Math.max(46, col.implicitHeight + 24)

    RowLayout {
        anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16; spacing: 16
        Label {
            text: root.label; color: Theme.text2
            Layout.preferredWidth: root.labelWidth; Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignTop; Layout.topMargin: 12
        }
        ColumnLayout {
            id: col
            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
            Layout.alignment: Qt.AlignTop; Layout.topMargin: 12
            Label {
                text: root.value !== "" ? root.value : "Unknown"
                color: root.value !== "" ? root.valueColor : Theme.text3
                font.features: { "tnum": 1 }
                horizontalAlignment: Text.AlignRight
                Layout.fillWidth: true; Layout.minimumWidth: 0
            }
            Label {
                visible: root.hint !== ""
                text: root.hint; color: Theme.text3; font.pixelSize: Theme.fsS
                horizontalAlignment: Text.AlignRight
                Layout.fillWidth: true; Layout.minimumWidth: 0
            }
            Item {
                id: under
                visible: root.showExtra && children.length > 0
                Layout.alignment: Qt.AlignRight; Layout.topMargin: 4
                implicitWidth: childrenRect.width; implicitHeight: childrenRect.height
            }
        }
    }
}
