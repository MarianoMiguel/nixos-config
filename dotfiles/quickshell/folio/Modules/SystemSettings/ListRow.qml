import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// A row in a list of things (devices, networks, layouts): an icon, a name and
// a line, and controls on the right (default property). Clickable when
// `clickable`; `selected` shows the ink tick, `busy` a turning arrow.
Item {
    id: root
    property string icon
    property string title
    property string subtitle
    property bool selected: false
    property bool clickable: true
    property bool busy: false
    property bool dim: false
    default property alias trailing: slot.data
    signal clicked()
    Layout.fillWidth: true
    implicitHeight: Math.max(52, text.implicitHeight + 18)

    Rectangle {
        anchors.fill: parent; anchors.margins: 3
        radius: Theme.inner(Theme.rM, 3)
        color: area.containsMouse && root.clickable ? Theme.wellStrong : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.tQuick } }
    }
    RowLayout {
        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 12; spacing: 12
        Rectangle {
            visible: root.icon !== ""
            Layout.preferredWidth: 30; Layout.preferredHeight: 30; radius: 9
            color: root.selected ? Theme.ink : Theme.rgba(Theme.ink, 0.12)
            Icon {
                anchors.centerIn: parent; name: root.busy ? "reload" : root.icon; size: 16
                color: root.selected ? Theme.inkText : Theme.ink
                RotationAnimation on rotation { running: root.busy; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
            }
        }
        ColumnLayout {
            id: text
            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 1
            opacity: root.dim ? 0.6 : 1
            Label { text: root.title; font.weight: root.selected ? Font.DemiBold : Font.Medium; Layout.fillWidth: true }
            Label { visible: root.subtitle !== ""; text: root.subtitle; color: Theme.text2; font.pixelSize: Theme.fsS; Layout.fillWidth: true }
        }
        Item { id: slot; implicitWidth: childrenRect.width; implicitHeight: childrenRect.height; Layout.alignment: Qt.AlignVCenter }
        Icon {
            visible: root.selected && root.icon === ""
            name: "check"; size: 16; stroke: 2.2; color: Theme.ink
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        enabled: root.clickable
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
