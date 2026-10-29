import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// A quick tile: a round badge that fills with ink when on, a title and a
// state line that elides. Pressing toggles; an expandable tile has a
// chevron of its own that opens its list below the tiles.
SideTap {
    id: root

    property bool on
    property string icon
    property string title
    property string sub
    property bool expandable: false
    property bool expanded: false
    property bool readOnly: false
    signal expand()

    implicitHeight: 58
    radius: Theme.inner(26, 14)
    stamp: !readOnly
    sink: !readOnly

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.hovered && !root.readOnly ? Theme.wellStrong : Theme.well
        border.width: 1
        border.color: root.expanded ? Theme.ruleStrong : Theme.rule
        Behavior on color { ColorAnimation { duration: Theme.tQuick } }
    }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: root.expandable ? 4 : 12
        spacing: 11
        Rectangle {
            implicitWidth: 32
            implicitHeight: 32
            radius: 16
            color: root.on ? Theme.ink : Theme.wellStrong
            Behavior on color { ColorAnimation { duration: Theme.tQuick } }
            Icon { anchors.centerIn: parent; name: root.icon; size: 17; color: root.on ? Theme.inkText : Theme.text }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 1
            Label { text: root.title; font.pixelSize: Theme.fsS; font.weight: Font.DemiBold; Layout.fillWidth: true; Layout.minimumWidth: 0 }
            Label { text: root.sub; visible: text !== ""; font.pixelSize: Theme.fsS - 1; color: Theme.text2; Layout.fillWidth: true; Layout.minimumWidth: 0 }
        }
        SideTap {
            visible: root.expandable
            Layout.leftMargin: -7
            implicitWidth: 24
            implicitHeight: 46
            radius: Theme.inner(Theme.inner(26, 14), 6)
            stamp: false
            onClicked: root.expand()
            Rectangle { anchors.fill: parent; radius: parent.radius; color: parent.hovered ? Theme.wellStrong : "transparent" }
            Icon {
                anchors.centerIn: parent
                name: "down"
                size: 16
                color: Theme.text2
                rotation: root.expanded ? 180 : 0
                Behavior on rotation { SpringPress {} }
            }
        }
    }
}
