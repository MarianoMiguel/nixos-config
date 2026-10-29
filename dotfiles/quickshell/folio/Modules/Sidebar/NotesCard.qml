import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// Notifications, a card per app, newest first: three cards and a row that
// opens the rest. Clear and × undo through a toast. Says when Focus is
// holding them, and "All caught up" when there are none.
ColumnLayout {
    id: root
    required property var feed
    property bool showAll: false
    property var expanded: ({})         // app -> true
    spacing: 6

    readonly property var groups: feed.groups
    readonly property var shown: showAll ? groups : groups.slice(0, 3)
    readonly property var rest: showAll ? [] : groups.slice(3)

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        Layout.rightMargin: 2
        Layout.topMargin: 6
        Layout.preferredHeight: 26
        Cap { text: "Notifications"; Layout.fillWidth: true; Layout.minimumWidth: 0 }
        SideButton {
            visible: root.groups.length > 0
            kind: "ghost"; text: "Clear"; size: 26; fontSize: Theme.fsS - 0.5
            implicitWidth: implicitHeight + 22
            onClicked: { root.showAll = false; root.feed.clearAll(); }
        }
    }

    // Focus is holding them.
    RowLayout {
        visible: root.feed.quiet
        Layout.fillWidth: true
        Layout.leftMargin: 6
        Layout.rightMargin: 6
        spacing: 8
        Icon { name: "moon"; size: 15; color: Theme.ink }
        Label {
            text: (root.feed.quietReason === "dnd" ? "Do not disturb is on" : root.feed.quietReason === "schedule" ? "Quiet hours" : "Focus is on")
                  + ": new notifications wait" + (root.feed.focusActive ? " until " + Qt.formatTime(new Date(root.feed.focusEnds), "HH:mm") : "")
            color: Theme.text2
            font.pixelSize: Theme.fsS
            Layout.fillWidth: true
            Layout.minimumWidth: 0
        }
    }

    Repeater {
        model: root.shown
        NoteCard {
            required property var modelData
            Layout.fillWidth: true
            feed: root.feed
            group: modelData
            expanded: !!root.expanded[modelData.app]
            onToggled: { const e = Object.assign({}, root.expanded); e[modelData.app] = !e[modelData.app]; root.expanded = e; }
        }
    }

    // The rest, summed up.
    SideTap {
        id: more
        visible: root.rest.length > 0
        Layout.fillWidth: true
        implicitHeight: 38
        radius: Theme.rS
        onClicked: root.showAll = true
        Rectangle { anchors.fill: parent; radius: parent.radius; color: more.hovered ? Theme.wellStrong : Theme.well; border.width: 1; border.color: Theme.rule }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 8
            Label {
                text: root.rest.reduce((a, g) => a + g.count, 0) + " more from " + root.rest.map(g => g.app).join(", ")
                Layout.fillWidth: true
                Layout.minimumWidth: 0
            }
            Icon { name: "down"; size: 16; color: Theme.text2 }
        }
    }

    // None
    SideCard {
        visible: root.groups.length === 0
        Layout.fillWidth: true
        implicitHeight: empty.implicitHeight + 36
        ColumnLayout {
            id: empty
            anchors.centerIn: parent
            width: parent.width - 28
            spacing: 4
            Icon { Layout.alignment: Qt.AlignHCenter; name: "check"; size: 22; color: Theme.ink }
            Label { Layout.alignment: Qt.AlignHCenter; text: "All caught up"; font.weight: Font.DemiBold }
            Cap { Layout.alignment: Qt.AlignHCenter; text: root.feed.since ? "Nothing new since " + root.feed.since : "Nothing new" }
        }
    }
}
