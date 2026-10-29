import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// One line of the results: a section caption, a result with its picture, its
// name and a quieter second part, or the empty state. The selection (drawn by
// the list) is ink; text on it turns to paper.
Item {
    id: root
    property var item: ({})
    property bool selected: false
    property bool inked: false          // the ink selection is under this row
    property bool showNumber: false     // Ctrl is held: show 1-9
    signal hovered(point at)            // in window coordinates
    signal activated()

    readonly property bool header: item.kind === "header"
    readonly property bool empty: item.kind === "empty"
    implicitHeight: item.h || 40

    // Nothing found: said plainly, with what to try next.
    ColumnLayout {
        visible: root.empty
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 32; rightMargin: 32 }
        spacing: 0
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 44
            implicitHeight: 44
            radius: 22
            color: Theme.well
            border.width: 1
            border.color: Theme.rule
            Icon { anchors.centerIn: parent; name: root.item.glyph || "search"; size: 20; color: Theme.text3 }
        }
        Label {
            text: root.item.title || ""
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.topMargin: 14
        }
        Label {
            text: root.item.subtitle || ""
            font.pixelSize: Theme.fsS
            color: Theme.text3
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.topMargin: 4
        }
    }

    Cap {
        visible: root.header
        text: root.item.title || ""
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 20; rightMargin: 20; bottomMargin: 8 }
    }

    RowLayout {
        visible: !root.header && !root.empty
        anchors { fill: parent; leftMargin: 18; rightMargin: 16 }
        spacing: 12

        ResultIcon {
            size: 26
            icon: root.item.icon || ""
            glyph: root.item.glyph || "grid"
            mark: root.item.mark || ""
            emoji: root.item.emoji || ""
            inverted: root.inked
            Layout.alignment: Qt.AlignVCenter
        }
        // The name, then a quieter second part. Short second parts stay
        // whole; the name gives way first, down to 60% of the line.
        Item {
            id: texts
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.fillHeight: true
            readonly property real room: subtitle.text ? Math.min(subtitle.implicitWidth, 96) + 10 : 0
            Label {
                id: title
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Math.max(parent.width * 0.6, parent.width - texts.room))
                text: root.item.title || ""
                font.weight: Font.Medium
                color: root.inked ? Theme.paper : Theme.text
            }
            Label {
                id: subtitle
                anchors.verticalCenter: parent.verticalCenter
                x: title.width + 10
                width: Math.max(0, parent.width - x)
                visible: width > 28
                text: root.item.subtitle || ""
                // A folder keeps both ends: "~/Documents/…/Drafts".
                elide: root.item.kind === "file" ? Text.ElideMiddle : Text.ElideRight
                font.pixelSize: Theme.fsS
                color: root.inked ? Theme.rgba(Theme.paper, 0.72) : Theme.text3
            }
        }
        KeyCap {
            visible: root.showNumber && root.item.number > 0
            text: String(root.item.number)
            inverted: root.inked
        }
        KeyCap {
            visible: root.selected && root.inked && !root.showNumber
            text: "↵"
            inverted: true
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.header && !root.empty
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: mouse => root.hovered(mapToItem(null, mouse.x, mouse.y))
        onClicked: root.activated()
    }
}
