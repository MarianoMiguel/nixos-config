import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Widgets

// What waited while the screen was locked: one slip of paper per app,
// newest app first, with how many it sent. A slip shows the app's latest
// notification; opening it (click, or the arrow keys) shows the latest
// three. With previews off ("lock.previews": never) a slip is only the app
// and its count, and nothing opens. Nothing here acts on a notification:
// no replies, no dismissing, no default action while locked.
Item {
    id: root
    required property var lock
    property real maxHeight: 400

    readonly property var groups: lock.notes
    readonly property bool previews: lock.previews
    readonly property int total: groups.reduce((s, g) => s + g.count, 0)
    readonly property string quiet: ({ "focus": "Focus", "dnd": "Do not disturb", "schedule": "Quiet hours" })[lock.notesQuiet] || ""

    visible: groups.length > 0
    implicitHeight: groups.length ? head.height + 12 + list.height : 0
    // Everything, uncapped: the page makes room for this much when it can.
    readonly property real naturalHeight: groups.length ? head.height + 12 + list.contentHeight : 0

    function countText(n) { return n > 99 ? "99+" : String(n); }
    function iconSource(icon) {
        if (!icon) return "";
        if (icon.indexOf("/") === 0) return "file://" + icon;
        if (/^(file|image|qrc):/.test(icon)) return icon;
        return Quickshell.iconPath(icon, true) || "";
    }

    Row {
        id: head
        spacing: 10
        Cap {
            anchors.verticalCenter: parent.verticalCenter
            text: root.total === 1 ? "1 notification" : root.countText(root.total) + " notifications"
            color: Theme.text2
            font.pixelSize: 12
        }
        Cap {
            visible: root.quiet !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: "· " + root.quiet
            font.pixelSize: 12
        }
    }

    ListView {
        id: list
        anchors.top: head.bottom
        anchors.topMargin: 12
        width: parent.width
        height: Math.min(contentHeight, Math.max(0, root.maxHeight - head.height - 12))
        clip: true
        spacing: 10
        boundsBehavior: Flickable.StopAtBounds
        model: root.groups
        // Keep the open slip in view when the keys move through them.
        readonly property int openIndex: root.groups.findIndex(g => g.app === root.lock.notesOpen)
        onOpenIndexChanged: if (openIndex >= 0) Qt.callLater(() => list.positionViewAtIndex(list.openIndex, ListView.Contain))

        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.tPanel }
        }
        displaced: Transition {
            NumberAnimation { property: "y"; duration: Theme.tPanel; easing.type: Easing.OutCubic }
        }

        delegate: Item {
            id: slip
            required property var modelData
            required property int index
            readonly property var g: modelData
            readonly property bool open: root.previews && root.lock.notesOpen === g.app
            readonly property var shown: !root.previews ? [] : open ? g.items.slice(0, 3) : g.items.slice(0, 1)
            readonly property int more: open ? Math.max(0, g.count - shown.length) : 0
            // Collapsed groups of more than one show the slips under them.
            readonly property int under: open ? 0 : Math.min(2, g.count - 1)
            readonly property real r: Theme.rM

            width: ListView.view.width
            height: card.height + under * 5

            // The slips underneath, each a little narrower and paler.
            Repeater {
                model: slip.under
                Rectangle {
                    required property int index
                    readonly property int depth: slip.under - index
                    x: depth * 9
                    width: slip.width - depth * 18
                    y: card.height - slip.r * 2 + depth * 5
                    height: slip.r * 2
                    radius: slip.r
                    color: Theme.mix(Theme.sheetBase, Theme.paper, 0.35 + depth * 0.2)
                    border.width: 1
                    border.color: Theme.rule
                }
            }
            RectangularShadow {
                anchors.fill: card
                radius: slip.r
                blur: 10
                offset: Qt.vector2d(0, 2)
                color: Theme.rgba(Theme.shade, Theme.dark ? 0.32 : 0.07)
            }
            Rectangle {
                id: card
                width: parent.width
                height: col.implicitHeight + 26
                radius: slip.r
                color: Theme.sheetStrong
                border.width: slip.open ? 2 : 1
                border.color: slip.open ? Theme.ink : Theme.rule
                clip: true
                Behavior on height { SpringPanel {} }

                ColumnLayout {
                    id: col
                    anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16; topMargin: 13 }
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        ClippingRectangle {
                            implicitWidth: 26; implicitHeight: 26
                            radius: 7
                            color: appIcon.visible ? "transparent" : Theme.ink
                            Image {
                                id: appIcon
                                anchors.fill: parent
                                source: root.iconSource(slip.g.icon)
                                sourceSize: Qt.size(52, 52)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                visible: status === Image.Ready
                            }
                            Text {
                                visible: !appIcon.visible
                                anchors.centerIn: parent
                                text: (slip.g.app || "?").charAt(0).toUpperCase()
                                color: Theme.inkText
                                font.family: Theme.hero
                                font.pixelSize: 17
                            }
                        }
                        Label {
                            text: slip.g.app
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                        }
                        // The count: a badge beside the preview, words without one.
                        Rectangle {
                            visible: root.previews && slip.g.count > 1
                            implicitWidth: Math.max(22, badge.implicitWidth + 12)
                            implicitHeight: 22
                            radius: 11
                            color: Theme.ink
                            Text {
                                id: badge
                                anchors.centerIn: parent
                                text: root.countText(slip.g.count)
                                color: Theme.inkText
                                font.family: Theme.ui
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                font.features: ({ "tnum": 1 })
                            }
                        }
                        Label {
                            visible: !root.previews
                            text: slip.g.count === 1 ? "1 notification" : root.countText(slip.g.count) + " notifications"
                            color: Theme.text2
                            font.pixelSize: 14
                        }
                        Cap {
                            text: slip.g.ago
                            font.pixelSize: 12
                        }
                    }

                    Repeater {
                        model: slip.shown
                        ColumnLayout {
                            id: note
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 3
                            Rectangle {
                                visible: note.index > 0
                                Layout.fillWidth: true
                                Layout.bottomMargin: 6
                                implicitHeight: 1
                                color: Theme.rule
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Label {
                                    text: note.modelData.summary || slip.g.app
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                }
                                Cap {
                                    visible: note.index > 0 && note.modelData.ago !== slip.g.ago
                                    text: note.modelData.ago
                                    font.pixelSize: 12
                                }
                            }
                            Text {
                                visible: text !== ""
                                Layout.fillWidth: true
                                text: note.modelData.body
                                color: Theme.text2
                                font.family: Theme.ui
                                font.pixelSize: 14
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                lineHeight: 1.1
                            }
                        }
                    }
                    Cap {
                        visible: slip.more > 0
                        text: "+ " + slip.more + " more"
                        Layout.fillWidth: true
                        font.pixelSize: 12
                    }
                }
            }
            MouseArea {
                anchors.fill: card
                enabled: root.previews
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.lock.notesOpen = slip.open ? "" : slip.g.app
            }
        }
    }

    // More below: the page's paper fades the last slip out.
    Rectangle {
        visible: !list.atYEnd
        anchors { left: list.left; right: list.right; bottom: list.bottom }
        height: 44
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.rgba(Theme.paper, 0) }
            GradientStop { position: 1; color: Theme.paper }
        }
    }
}
