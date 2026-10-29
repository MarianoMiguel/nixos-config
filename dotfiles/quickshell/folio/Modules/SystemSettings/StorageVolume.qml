import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// One internal filesystem on Storage & drives: its name and what is free, a
// usage bar, how much is used and what it holds. Near full it says so and
// offers the way to Reclaim space.
Item {
    id: root
    property var volume: ({})
    property string note: ""
    signal reclaim()

    readonly property real total: (volume.used || 0) + (volume.free || 0)
    readonly property real frac: total > 0 ? volume.used / total : 0
    readonly property bool full: frac >= 0.9
    readonly property bool critical: frac >= 0.97
    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + 28

    RowLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12
        Rectangle {
            Layout.preferredWidth: 30; Layout.preferredHeight: 30
            Layout.alignment: Qt.AlignTop
            radius: 9
            color: Theme.ink
            Icon { anchors.centerIn: parent; name: "drive"; size: 16; color: Theme.inkText }
        }
        ColumnLayout {
            id: body
            Layout.fillWidth: true; Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignTop
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Label { text: root.volume.name || ""; font.weight: Font.Medium; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                Label {
                    text: Drives.bytes(root.volume.free) + " free"
                    font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                    color: root.critical ? Theme.error : root.full ? Theme.warning : Theme.text
                    Behavior on color { ColorAnimation { duration: Theme.tQuick } }
                }
            }
            StorageBar { Layout.fillWidth: true; Layout.topMargin: 2; value: root.frac }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                ColumnLayout {
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    spacing: 1
                    Label {
                        text: (root.critical ? "Almost full · " : "") + Drives.bytes(root.volume.used) + " of " + Drives.bytes(root.volume.size) + " used"
                        color: root.critical ? Theme.error : Theme.text2
                        font.pixelSize: Theme.fsS
                        font.features: { "tnum": 1 }
                        Layout.fillWidth: true
                    }
                    Label {
                        visible: root.note !== ""
                        text: root.note
                        color: Theme.text3
                        font.pixelSize: Theme.fsS
                        Layout.fillWidth: true
                    }
                }
                Button {
                    visible: root.full
                    text: "Reclaim space"
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: root.reclaim()
                }
            }
        }
    }
}
