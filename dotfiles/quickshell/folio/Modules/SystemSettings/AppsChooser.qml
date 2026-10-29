import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// One kind of default (Web browser, Mail…): the kind and what it covers, and
// the current app as a select (the controls study). Open, the apps that can
// take it are listed in place, the current one ticked; choosing one closes
// it. Read-only shows the current app without the chevron.
Item {
    id: root
    property var row: ({ "kind": {}, "current": null, "candidates": [] })
    property bool expanded: false
    property bool readOnly: false
    property bool first: false
    signal toggled()
    signal chosen(string id)

    readonly property var kind: row.kind || {}
    readonly property var current: row.current
    readonly property var candidates: row.candidates || []
    readonly property bool canOpen: !readOnly && candidates.length > 0
    readonly property bool open: expanded && canOpen

    Layout.fillWidth: true
    implicitHeight: head.height + (open ? list.implicitHeight + 6 : 0)
    clip: true
    Behavior on implicitHeight { SpringPanel {} }

    Rectangle { visible: !root.first; x: 14; width: root.width - 28; height: 1; color: Theme.rule }

    Item {
        id: head
        width: root.width
        height: Math.max(58, words.implicitHeight + 22)
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 12; spacing: 12
            Rectangle {
                Layout.preferredWidth: 30; Layout.preferredHeight: 30; radius: 9; color: Theme.ink
                Icon { anchors.centerIn: parent; name: root.kind.icon || "apps"; size: 16; color: Theme.inkText }
            }
            ColumnLayout {
                id: words
                Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 1
                Label { text: root.kind.title || ""; font.weight: Font.Medium; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                Label {
                    text: root.candidates.length === 0 && !root.current ? "No installed app opens these" : (root.kind.what || "")
                    color: Theme.text2; font.pixelSize: Theme.fsS; Layout.fillWidth: true; Layout.minimumWidth: 0
                }
            }
            // The select: the current app, a chevron that turns when open.
            Rectangle {
                id: pick
                Layout.preferredWidth: Math.min(300, pickRow.implicitWidth + 22)
                Layout.preferredHeight: 34
                radius: Theme.rS
                color: root.readOnly ? "transparent" : (area.containsMouse && root.canOpen ? Theme.wellStrong : Theme.well)
                border.width: 1
                border.color: root.open ? Theme.ruleStrong : Theme.rule
                Behavior on color { ColorAnimation { duration: Theme.tQuick } }
                scale: area.pressed && root.canOpen ? 0.97 : 1
                Behavior on scale { SpringPress {} }
                RowLayout {
                    id: pickRow
                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 10; spacing: 8
                    AppsIcon { visible: !!root.current; icon: root.current ? root.current.icon : ""; name: root.current ? root.current.name : ""; size: 20 }
                    Label {
                        text: root.current ? root.current.name : "None"
                        color: root.current ? Theme.text : Theme.text2
                        font.pixelSize: Theme.fsS + 0.5
                        Layout.fillWidth: true; Layout.minimumWidth: 0
                        Layout.leftMargin: root.current ? 0 : 4
                    }
                    Icon {
                        visible: root.canOpen
                        name: "down"; size: 14; color: Theme.text2
                        rotation: root.open ? 180 : 0
                        Behavior on rotation { SpringPress {} }
                    }
                    Icon { visible: root.readOnly; name: "lock"; size: 13; color: Theme.text3 }
                }
            }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.canOpen
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled()
        }
    }

    ColumnLayout {
        id: list
        y: head.height
        width: root.width
        spacing: 0
        opacity: root.open ? 1 : 0
        Behavior on opacity { SpringSoft {} }
        Repeater {
            model: root.open || root.height > head.height + 1 ? root.candidates : []
            Item {
                id: cand
                required property var modelData
                readonly property bool on: !!root.current && root.current.id === modelData.id
                Layout.fillWidth: true
                implicitHeight: 42
                Rectangle {
                    anchors.fill: parent; anchors.leftMargin: 50; anchors.rightMargin: 8; anchors.topMargin: 1; anchors.bottomMargin: 1
                    radius: Theme.inner(Theme.rM, 4)
                    color: candArea.containsMouse ? Theme.wellStrong : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.tQuick } }
                }
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 58; anchors.rightMargin: 20; spacing: 10
                    AppsIcon { icon: cand.modelData.icon; name: cand.modelData.name; size: 22 }
                    Label {
                        text: cand.modelData.name
                        font.weight: cand.on ? Font.DemiBold : Font.Normal
                        Layout.fillWidth: true; Layout.minimumWidth: 0
                    }
                    Label {
                        visible: cand.modelData.generic !== "" && cand.modelData.generic !== cand.modelData.name
                        text: cand.modelData.generic
                        color: Theme.text3; font.pixelSize: Theme.fsS
                        Layout.maximumWidth: 160
                    }
                    Icon { name: "check"; size: 16; stroke: 2.2; color: Theme.ink; opacity: cand.on ? 1 : 0 }
                }
                MouseArea {
                    id: candArea
                    anchors.fill: parent; anchors.leftMargin: 50
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.chosen(cand.modelData.id)
                }
            }
        }
    }
}
