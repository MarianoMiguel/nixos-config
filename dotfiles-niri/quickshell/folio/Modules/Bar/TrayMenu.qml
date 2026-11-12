import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets

// A tray app's menu, drawn as a Folio sheet under its icon. Submenus open in
// place with a back row. While open, the window covers the screen so a click
// anywhere else (or Esc) closes it. The keyboard: Up and Down light a row
// (from nothing lit, Down the first and Up the last), Home and End, Return,
// Enter or Space choose it, Right opens a submenu at its first row, Left and
// Esc go back a level (Esc closes at the top).
PanelWindow {
    id: root

    property var bar
    property var item: null                // the SystemTrayItem
    property Item anchorItem: null
    property var stack: []                 // open submenu entries
    property real natural: 0               // widest row
    property real centerX: 0               // the icon's middle, in screen coordinates
    readonly property real pad: 6
    // Test data instead of an app's menu (Tray's IPC: tray menu normal):
    // plain entries with the same fields, children for submenus.
    property var fixture: null
    property string lastChosen: ""

    function show(trayItem, at) {
        if (visible && item === trayItem && !fixture) { close(); return; }
        item = trayItem;
        anchorItem = at;
        stack = [];
        trail = [];
        hot = null;
        natural = 0;
        centerX = at.mapToItem(bar.contentItem, at.width / 2, 0).x;
        visible = true;
        sheet.opacity = 0; sheet.drop = -4;
        enter.restart();
        keys.forceActiveFocus();
    }
    function showFixture(list, at) { fixture = list; show(null, at); }
    function close() { visible = false; stack = []; trail = []; hot = null; fixture = null; }
    function trigger(entry) {
        if (!entry || entry.isSeparator || !entry.enabled) return;
        if (entry.hasChildren) { natural = 0; stack = stack.concat([entry]); return; }
        lastChosen = entry.text || "";
        entry.triggered();
        close();
    }

    // ------------------------------------------------------------ keyboard

    property Item hot: null                // the lit row, the pointer's or the keyboard's
    // A long menu scrolls to keep the keyboard's row in view.
    function keepInView() { if (hot && flick.interactive) flick.contentY = KeyNav.scrollFor(flick, hot, 4); }
    property var trail: []                 // the row (index) each open submenu came from
    property int wantRow: -1               // light this row once the level's rows exist
    function rows() { return Array.prototype.filter.call(list.children, c => c.isRow === true && c.visible && !c.separator && c.enabled_); }
    function entries() { return rows().filter(r => r !== backRow); }
    function step(d) {
        const all = rows();
        if (!all.length) return;
        const i = all.indexOf(hot);
        hot = all[i < 0 ? (d > 0 ? 0 : all.length - 1) : (i + d + all.length) % all.length];
    }
    function enterSub() {
        if (!hot || !hot.entry || !hot.entry.hasChildren) return;
        trail = trail.concat([entries().indexOf(hot)]);
        wantRow = 0;
        trigger(hot.entry);
        hot = null;
        lightSoon();
    }
    function back() {
        if (!stack.length) return false;
        wantRow = trail.length ? trail[trail.length - 1] : -1;
        trail = trail.slice(0, -1);
        stack = stack.slice(0, -1);
        hot = null;
        lightSoon();
        return true;
    }
    // A level's rows can arrive a moment after it opens (an app's menu
    // loads on demand), so lighting the wanted row waits for them.
    function lightSoon() { Qt.callLater(light); }
    function light() {
        if (wantRow < 0) return;
        const e = entries();
        if (!e.length) return;
        hot = e[Math.min(wantRow, e.length - 1)];
        wantRow = -1;
        keepInView();
    }
    function choose() {
        if (!hot) return;
        if (hot === backRow) { back(); return; }
        if (hot.entry && hot.entry.hasChildren) { enterSub(); return; }
        trigger(hot.entry);
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
    QsMenuOpener { id: subMenu; menu: !root.fixture && root.stack.length ? root.stack[root.stack.length - 1] : null }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: root.close()
    }
    Item {
        id: keys
        focus: true
        Keys.onPressed: event => {
            const k = event.key;
            if (k === Qt.Key_Escape) { if (!root.back()) root.close(); }
            else if (k === Qt.Key_Down) root.step(1);
            else if (k === Qt.Key_Up) root.step(-1);
            else if (k === Qt.Key_Home) { root.hot = null; root.step(1); }
            else if (k === Qt.Key_End) { root.hot = null; root.step(-1); }
            else if (k === Qt.Key_Right) root.enterSub();
            else if (k === Qt.Key_Left) root.back();
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { if (!event.isAutoRepeat) root.choose(); }
            else return;
            root.keepInView();
            event.accepted = true;
        }
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
            id: flick
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
                    id: backRow
                    width: list.width
                    visible: root.stack.length > 0
                    icon: "back"
                    label: root.stack.length ? (root.stack[root.stack.length - 1].text || "Back") : ""
                    bold: true
                    onActivated: root.back()
                    // A long submenu title widens the sheet (up to its cap) and elides.
                    onImplicitWidthChanged: root.natural = Math.max(root.natural, implicitWidth)
                }
                Repeater {
                    model: root.fixture ? (root.stack.length ? root.stack[root.stack.length - 1].children || [] : root.fixture)
                         : root.stack.length ? subMenu.children : rootMenu.children
                    onItemAdded: if (root.wantRow >= 0) root.lightSoon()
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
        readonly property bool isRow: true
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
            // The lit row, firm enough to follow from the keyboard.
            color: root.hot === r && r.enabled_ ? Theme.wellStrong : Theme.rgba(Theme.ink, 0)
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
            onEntered: if (r.enabled_) root.hot = r
            onExited: if (root.hot === r) root.hot = null
            onClicked: r.activated()
        }
    }
}
