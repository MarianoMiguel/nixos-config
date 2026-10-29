import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// The power menu: a small sheet that prints up from the Power button.
// Each action counts down in a toast (Cancel stops it); hibernating locks
// first. The sidebar closes so the toast shows.
Item {
    id: root
    property bool open: false
    signal chosen(string what)

    readonly property var items: [
        { "id": "hibernate", "icon": "moon", "text": "Hibernate" },
        { "id": "reboot", "icon": "reload", "text": "Restart" },
        { "id": "poweroff", "icon": "power", "text": "Shut down" },
        { "id": "logout", "icon": "user", "text": "Log out" }
    ]

    implicitWidth: 196
    implicitHeight: col.implicitHeight + 12
    visible: t > 0.01
    // 0..1 on a spring: it grows from its bottom-right corner.
    property real t: open ? 1 : 0
    Behavior on t { SpringSoft {} }
    opacity: Math.min(1, t)
    transform: Scale { origin.x: root.width; origin.y: root.height; xScale: 0.94 + 0.06 * root.t; yScale: 0.94 + 0.06 * root.t }

    Sheet {
        anchors.fill: parent
        radius: Theme.rM
        color: Theme.sheetStrong
        elevation: 0.6
    }
    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
        spacing: 0
        Repeater {
            model: root.items
            SideTap {
                id: item
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 32
                radius: Theme.inner(Theme.rM, 6)
                sink: false
                onClicked: root.chosen(modelData.id)
                Rectangle { anchors.fill: parent; radius: parent.radius; color: item.hovered ? Theme.ink : "transparent" }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10
                    Icon { name: item.modelData.icon; size: 16; color: item.hovered ? Theme.inkText : Theme.text }
                    Label { text: item.modelData.text; color: item.hovered ? Theme.inkText : Theme.text; Layout.fillWidth: true }
                }
            }
        }
    }
}
