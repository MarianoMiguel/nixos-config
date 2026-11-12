import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Widgets

// One app's notifications: the newest in full (summary, a two-line body,
// its actions), a count badge, and the rest a click away. Hovering shows ×
// to dismiss; clicking a notification runs its default action.
Item {
    id: root
    required property var feed
    required property var group
    property bool expanded: false
    signal toggled()

    readonly property var newest: group.items[0]
    readonly property var older: group.items.slice(1, 6)
    readonly property int unseen: Math.max(0, group.count - 1 - older.length)
    readonly property real r: Theme.inner(26, 14)

    implicitHeight: col.implicitHeight + 24

    RectangularShadow {
        anchors.fill: bg
        radius: root.r
        blur: 8
        offset: Qt.vector2d(0, 2)
        color: Theme.rgba(Theme.shade, Theme.dark ? 0.3 : 0.08)
    }
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: root.r
        color: Theme.sheetStrong
        border.width: 1
        border.color: Theme.rule
    }

    component Avatar: ClippingRectangle {
        id: avatar
        property var note
        implicitWidth: 30
        implicitHeight: 30
        radius: 9
        color: art.visible ? "transparent" : Theme.ink
        readonly property string source: note.image ? (note.image.indexOf("/") === 0 ? "file://" + note.image : note.image) : note.icon ? Quickshell.iconPath(note.icon, true) : ""
        Image {
            id: art
            anchors.fill: parent
            source: avatar.source
            sourceSize: Qt.size(60, 60)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
        }
        Text {
            visible: !art.visible
            anchors.centerIn: parent
            text: (root.group.app || "?").charAt(0).toUpperCase()
            color: Theme.inkText
            font.family: Theme.hero; font.weight: Theme.heroWeight
            font.pixelSize: 18
        }
    }

    // One notification: summary, ago, ×; the body under it.
    component Note: SideTap {
        id: note
        property var item
        property bool lead: false
        sink: false
        stamp: false
        // Its text runs to its edges, so the keyboard's ring sits outside.
        ringInside: false
        implicitHeight: lines.implicitHeight
        onClicked: root.feed.activate(item)
        // Delete dismisses it from the keyboard, as × does.
        Keys.onDeletePressed: root.feed.dismiss([note.item])
        HoverHandler { id: hover }
        ColumnLayout {
            id: lines
            width: parent.width
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Label { text: note.item.summary || root.group.app; font.weight: Font.DemiBold; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                Rectangle {
                    visible: note.lead && root.group.count > 1
                    implicitWidth: Math.max(18, badge.implicitWidth + 10)
                    implicitHeight: 18
                    radius: 9
                    color: Theme.ink
                    Text {
                        id: badge
                        anchors.centerIn: parent
                        text: root.group.count > 99 ? "99+" : root.group.count
                        color: Theme.inkText
                        font.family: Theme.ui
                        font.pixelSize: Theme.fsCap
                        font.weight: Font.DemiBold
                        font.features: ({ "tnum": 1 })
                    }
                }
                Label {
                    visible: !closeBtn.visible
                    text: { root.feed.now; return root.feed.ago(note.item); }
                    color: Theme.text3
                    font.pixelSize: Theme.fsCap + 0.5
                }
                SideButton {
                    id: closeBtn
                    // For the pointer on hover; for the keyboard while the note has it.
                    visible: hover.hovered || note.activeFocus || activeFocus
                    kind: "ghost"; round: true; size: 20; iconSize: 12; icon: "close"
                    onClicked: root.feed.dismiss([note.item])
                }
            }
            Text {
                visible: text !== ""
                text: note.item.body
                Layout.fillWidth: true
                color: Theme.text2
                font.family: Theme.ui
                font.pixelSize: Theme.fsS
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                textFormat: Text.PlainText
                lineHeight: 1.1
            }
        }
    }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 12; topMargin: 12 }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Avatar { note: root.newest; Layout.alignment: Qt.AlignTop }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 8
                Note { item: root.newest; lead: true; Layout.fillWidth: true }
                // Actions
                Flow {
                    visible: root.newest.actions.length > 0
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: root.newest.actions
                        SideButton {
                            required property var modelData
                            text: modelData.text
                            size: 26
                            fontSize: Theme.fsS - 0.5
                            width: Math.min(implicitWidth, parent.width)
                            onClicked: root.feed.activate(root.newest, modelData)
                        }
                    }
                }
                // The rest of the group
                Repeater {
                    model: root.expanded ? root.older : []
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.rule }
                        Note { item: parent.modelData; Layout.fillWidth: true }
                    }
                }
                Cap {
                    visible: root.expanded && root.unseen > 0
                    text: root.unseen + " more"
                }
                // Expand or collapse
                SideTap {
                    id: more
                    visible: root.group.items.length > 1 || root.group.count > 1
                    Layout.fillWidth: true
                    implicitHeight: 16
                    sink: false
                    stamp: false
                    ringInside: false
                    onClicked: root.toggled()
                    RowLayout {
                        anchors.fill: parent
                        spacing: 6
                        Cap {
                            text: root.expanded ? "Show less" : (root.group.count - 1) + " more from " + root.group.app
                            color: more.hovered ? Theme.ink : Theme.text3
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                        }
                        Icon { name: "down"; size: 13; color: Theme.text3; rotation: root.expanded ? 180 : 0 }
                    }
                }
            }
        }
    }
}
