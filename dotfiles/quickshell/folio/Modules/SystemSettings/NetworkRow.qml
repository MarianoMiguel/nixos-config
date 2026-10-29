import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// A row for the Network and Bluetooth pages: ListRow's layout, with a badge
// that can show Wi-Fi strength or a device kind (NetworkGlyph), a lock for
// secured networks, and a panel that springs open under the row (`panel`, a
// Component, loaded only while open: the password field, pairing steps).
Item {
    id: root
    property string icon
    property int signal: -1
    property string title
    property string subtitle
    property color subtitleColor: Theme.text2
    property bool selected: false
    property bool clickable: true
    property bool busy: false
    property bool dim: false
    property bool secure: false
    property bool open: false
    property Component panel: null
    default property alias trailing: slot.data
    signal clicked()
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    implicitHeight: head.height + drawer.h

    Item {
        id: head
        width: parent.width
        height: Math.max(52, text.implicitHeight + 18)

        Rectangle {
            anchors.fill: parent; anchors.margins: 3
            radius: Theme.inner(Theme.rM, 3)
            color: area.containsMouse && root.clickable ? Theme.wellStrong : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.tQuick } }
        }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 12; spacing: 12
            Rectangle {
                Layout.preferredWidth: 30; Layout.preferredHeight: 30; radius: 9
                color: root.selected ? Theme.ink : Theme.rgba(Theme.ink, 0.12)
                opacity: root.dim ? 0.6 : 1
                NetworkGlyph {
                    anchors.centerIn: parent
                    visible: !root.busy
                    name: root.icon; signal: root.signal; size: 16
                    color: root.selected ? Theme.inkText : Theme.ink
                }
                Icon {
                    anchors.centerIn: parent
                    visible: root.busy
                    name: "reload"; size: 16
                    color: root.selected ? Theme.inkText : Theme.ink
                    RotationAnimation on rotation { running: root.busy; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                }
            }
            ColumnLayout {
                id: text
                Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 1
                opacity: root.dim ? 0.6 : 1
                RowLayout {
                    Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 6
                    Label { text: root.title; font.weight: root.selected ? Font.DemiBold : Font.Medium; Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.maximumWidth: Math.ceil(implicitWidth) + 1 }
                    Icon { visible: root.secure; name: "lock"; size: 12; color: Theme.text3 }
                    Item { Layout.fillWidth: true }
                }
                Label { visible: root.subtitle !== ""; text: root.subtitle; color: root.subtitleColor; font.pixelSize: Theme.fsS; Layout.fillWidth: true; Layout.minimumWidth: 0 }
            }
            Item { id: slot; implicitWidth: childrenRect.width; implicitHeight: childrenRect.height; Layout.alignment: Qt.AlignVCenter }
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

    // The panel under the row, sprung open and closed.
    Item {
        id: drawer
        property real h: root.open && loader.item ? loader.item.implicitHeight + 14 : 0
        Behavior on h { SpringPanel {} }
        y: head.height
        width: parent.width
        height: h
        clip: true
        visible: h > 0.5
        opacity: Math.min(1, h / 30)
        Loader {
            id: loader
            x: 56; width: parent.width - 56 - 14
            active: root.panel !== null && (root.open || drawer.h > 0.5)
            sourceComponent: root.panel
        }
    }
}
