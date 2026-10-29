import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// A setting with one choice from a list too long for segments: the row shows
// the current choice; pressing it opens the list right below, inside the card,
// on a spring. Picking one closes it.
Item {
    id: root
    property string icon
    property string label
    property string hint
    property var options: []            // [{value, label, note}]
    property var value
    property bool open: false
    signal chosen(var value)
    Layout.fillWidth: true
    implicitHeight: head.implicitHeight + drawer.height
    clip: true

    readonly property var current: options.find(o => o.value === value) || null

    // Keyboard: Space or Enter on the select opens the list at the current
    // choice; Up and Down move through it, Space or Enter picks, Escape
    // closes it and goes back to the select (Settings lets it have Escape).
    readonly property bool holdsEscape: open
    Keys.onEscapePressed: { root.open = false; pickBox.forceActiveFocus(); }
    function openByKey() {
        root.open = true;
        const i = Math.max(0, root.options.findIndex(o => o.value === root.value));
        Qt.callLater(() => { const it = optionRows.itemAt(i); if (it) it.forceActiveFocus(); });
    }
    function pick(v) {
        root.open = false;
        pickBox.forceActiveFocus();
        if (v !== root.value) root.chosen(v);
    }

    SettingRow {
        id: head
        width: parent.width
        icon: root.icon; label: root.label; hint: root.hint
        Item {
            id: pickBox
            implicitWidth: Math.min(240, pick.implicitWidth + 40)
            implicitHeight: 32
            activeFocusOnTab: true
            Keys.onPressed: event => KeyNav.press(event, () => { if (root.open) root.open = false; else root.openByKey(); })
            FocusRing { radius: Theme.rS }
            Rectangle {
                anchors.fill: parent; radius: Theme.rS
                color: area.containsMouse || root.open ? Theme.wellStrong : Theme.well
                border.color: root.open ? Theme.ruleStrong : Theme.rule
                Behavior on color { ColorAnimation { duration: Theme.tQuick } }
            }
            Label {
                id: pick
                x: 12; width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
                text: root.current ? root.current.label : "Not set"
                font.pixelSize: Theme.fsS; font.weight: Font.Medium
            }
            Icon {
                anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                name: "down"; size: 14; color: Theme.text2
                rotation: root.open ? 180 : 0
                Behavior on rotation { SpringPress {} }
            }
            MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.open = !root.open }
        }
    }

    Item {
        id: drawer
        y: head.height
        width: parent.width
        height: root.open ? list.implicitHeight + 8 : 0
        opacity: root.open ? 1 : 0
        visible: root.open || height > 0.5
        clip: true
        Behavior on height { SpringPanel {} }
        Behavior on opacity { SpringSoft {} }
        Rectangle { x: 14; width: parent.width - 28; height: 1; color: Theme.rule }
        Column {
            id: list
            x: 6; y: 4; width: parent.width - 12
            Repeater {
                id: optionRows
                model: root.options
                Item {
                    id: opt
                    required property var modelData
                    readonly property bool on: modelData.value === root.value
                    width: list.width
                    height: 36
                    activeFocusOnTab: root.open
                    Keys.onPressed: event => KeyNav.press(event, () => root.pick(opt.modelData.value))
                    FocusRing { radius: Theme.inner(Theme.rM, 6) + 1; gap: -1 }
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 1
                        radius: Theme.inner(Theme.rM, 6)
                        color: optArea.containsMouse ? Theme.well : "transparent"
                    }
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 52; anchors.rightMargin: 12; spacing: 10
                        Label { text: opt.modelData.label; font.weight: opt.on ? Font.DemiBold : Font.Normal; color: opt.on ? Theme.ink : Theme.text; Layout.fillWidth: !opt.modelData.note; Layout.minimumWidth: 0 }
                        Label { visible: !!opt.modelData.note; text: opt.modelData.note || ""; color: Theme.text3; font.pixelSize: Theme.fsS; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                        Icon { visible: opt.on; name: "check"; size: 15; stroke: 2.2; color: Theme.ink }
                    }
                    MouseArea {
                        id: optArea
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { root.open = false; if (!opt.on) root.chosen(opt.modelData.value); }
                    }
                }
            }
        }
    }
}
