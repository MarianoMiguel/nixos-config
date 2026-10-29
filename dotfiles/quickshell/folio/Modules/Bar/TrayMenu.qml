import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets

// A tray app's menu, drawn as a Folio sheet under its icon. Submenus open in
// place with a back row. While open, the window covers the screen so a click
// anywhere else (or Esc) closes it.
PanelWindow {
    id: root

    property var bar
    property var item: null                // the SystemTrayItem
    property Item anchorItem: null
    property var stack: []                 // open submenu entries
    property real natural: 0               // widest row
    property real centerX: 0               // the icon's middle, in screen coordinates
    readonly property real pad: 6

    function show(trayItem, at) {
        if (visible && item === trayItem) { close(); return; }
        item = trayItem;
        anchorItem = at;
        stack = [];
        natural = 0;
        centerX = at.mapToItem(bar.contentItem, at.width / 2, 0).x;
        visible = true;
        sheet.opacity = 0; sheet.drop = -4;
        enter.restart();
        keys.forceActiveFocus();
    }
    function close() { visible = false; stack = []; }
    function trigger(entry) {
        if (!entry || entry.isSeparator || !entry.enabled) return;
        if (entry.hasChildren) { natural = 0; stack = stack.concat([entry]); return; }
        entry.triggered();
        close();
    }

    screen: bar ? bar.screen : null
    visible: false
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "folio:tray-menu"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    BackgroundEffect.blurRegion: Region { item: sheet; radius: Theme.rM + frost.extra }
    BlurNudge { id: frost; key: root.visible }

    QsMenuOpener { id: rootMenu; menu: root.item ? root.item.menu : null }
    QsMenuOpener { id: subMenu; menu: root.stack.length ? root.stack[root.stack.length - 1] : null }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: root.close()
    }
    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: { if (root.stack.length) root.stack = root.stack.slice(0, -1); else root.close(); }
    }

    ParallelAnimation {
        id: enter
        SpringAnimation { target: sheet; property: "opacity"; to: 1; spring: 4; damping: 0.5; epsilon: 0.002 }
        SpringAnimation { target: sheet; property: "drop"; to: 0; spring: 7; damping: 0.42; mass: 0.6; epsilon: 0.05 }
    }

    Sheet {
        id: sheet
        property real drop: 0
        width: Math.max(180, Math.min(320, root.natural + root.pad * 2))
        height: Math.min(list.implicitHeight + root.pad * 2, root.height - 80)
        x: Math.max(8, Math.min(root.width - width - 8, Math.round(root.centerX - width / 2)))
        y: (root.bar ? root.bar.height : 34) + 6 + drop
        radius: Theme.rM
        color: Theme.sheetStrong
        MouseArea { anchors.fill: parent }        // clicks on the sheet stay on it

        Flickable {
            anchors.fill: parent
            anchors.margins: root.pad
            contentHeight: list.implicitHeight
            clip: contentHeight > height
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: list
                width: parent.width
                spacing: 1

                Row_ {
                    width: list.width
                    visible: root.stack.length > 0
                    icon: "back"
                    label: root.stack.length ? (root.stack[root.stack.length - 1].text || "Back") : ""
                    bold: true
                    onActivated: root.stack = root.stack.slice(0, -1)
                }
                Repeater {
                    model: root.stack.length ? subMenu.children : rootMenu.children
                    Row_ {
                        required property var modelData
                        width: list.width
                        entry: modelData
                        onActivated: root.trigger(modelData)
                        onImplicitWidthChanged: root.natural = Math.max(root.natural, implicitWidth)
                        Component.onCompleted: root.natural = Math.max(root.natural, implicitWidth)
                    }
                }
            }
        }
    }

    // One menu row: a separator, a plain item, a check or radio, a submenu.
    component Row_: Item {
        id: r
        property var entry: null
        property string icon: ""
        property string label: entry ? (entry.text || "") : ""
        property bool bold: false
        readonly property bool separator: !!entry && entry.isSeparator
        readonly property bool enabled_: !entry || entry.enabled
        signal activated()

        implicitWidth: rowContent.implicitWidth + 20 + (entry && entry.hasChildren ? 18 : 0)
        implicitHeight: separator ? 9 : 28

        Rectangle {
            visible: r.separator
            anchors.centerIn: parent
            width: parent.width - 12
            height: 1
            color: Theme.rule
        }
        Rectangle {
            visible: !r.separator
            anchors.fill: parent
            radius: Theme.inner(Theme.rM, 6)
            color: hover.containsMouse && r.enabled_ ? Theme.well : Theme.rgba(Theme.ink, 0)
            Behavior on color { ColorAnimation { duration: Theme.tPress } }
        }
        Row {
            id: rowContent
            visible: !r.separator
            anchors.verticalCenter: parent.verticalCenter
            x: 10
            spacing: 8
            // Check and radio marks.
            Item {
                readonly property int kind: r.entry ? r.entry.buttonType : 0
                visible: kind !== 0
                width: 14; height: 14
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    anchors.fill: parent
                    radius: parent.kind === 2 ? 7 : 4
                    color: r.entry && r.entry.checkState === Qt.Checked ? Theme.ink : Theme.rgba(Theme.ink, 0)
                    border.width: 1
                    border.color: r.entry && r.entry.checkState === Qt.Checked ? Theme.ink : Theme.ruleStrong
                }
                Icon {
                    anchors.centerIn: parent
                    visible: r.entry && r.entry.checkState === Qt.Checked && parent.kind === 1
                    name: "check"; size: 12; stroke: 2; color: Theme.inkText
                }
                Rectangle {
                    anchors.centerIn: parent
                    visible: r.entry && r.entry.checkState === Qt.Checked && parent.kind === 2
                    width: 6; height: 6; radius: 3; color: Theme.inkText
                }
            }
            Icon {
                visible: r.icon !== ""
                name: r.icon; size: 14; color: Theme.text2
                anchors.verticalCenter: parent.verticalCenter
            }
            Image {
                visible: !!r.entry && (r.entry.icon || "") !== "" && status === Image.Ready
                source: r.entry ? (r.entry.icon || "") : ""
                width: 16; height: 16
                sourceSize: Qt.size(32, 32)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                text: r.label
                font.pixelSize: Theme.fsS
                font.weight: r.bold ? Font.DemiBold : Font.Normal
                color: r.enabled_ ? Theme.text : Theme.text3
                width: Math.min(implicitWidth, Math.max(0, 300 - 60))
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Icon {
            visible: !!r.entry && r.entry.hasChildren
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            name: "right"; size: 13; color: Theme.text3
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            enabled: !r.separator
            hoverEnabled: true
            cursorShape: r.enabled_ ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: r.activated()
        }
    }
}
