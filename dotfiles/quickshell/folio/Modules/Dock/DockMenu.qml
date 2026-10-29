import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets

// An app's menu: prints in from the cursor, above it, and lifts off back
// into it. A transparent full-screen layer catches the click that closes it;
// the keyboard works: Up and Down (from nothing lit, Down lights the first
// and Up the last), Home and End, Return, Enter or Space choose, Escape.
PanelWindow {
    id: win

    property var items: []                 // [{ "label", "danger", "run" }] or { "rule": true }
    property string title: ""
    property point at: Qt.point(0, 0)
    property bool open: false
    property int current: -1
    signal dismissed()

    function popup(pos, heading, list) {
        at = pos; title = heading; items = list; current = -1;
        open = true;
        page.progress = 0;
        page.printIn(240);
        keys.forceActiveFocus();
    }
    function close() {
        if (!open) return;
        open = false;
        page.lift(160);
        win.dismissed();
    }
    function choose(i) {
        const it = items[i];
        if (!it || it.rule) return;
        close();
        it.run();
    }

    visible: open || page.running
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "folio:dock-menu"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    BackgroundEffect.blurRegion: Region { item: win.open ? sheet : null; radius: Theme.rM + frost.extra }
    BlurNudge { id: frost; key: win.open }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: win.close()
    }

    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: win.close()
        Keys.onUpPressed: win.step(-1)
        Keys.onDownPressed: win.step(1)
        Keys.onReturnPressed: win.choose(win.current)
        Keys.onEnterPressed: win.choose(win.current)
        Keys.onSpacePressed: win.choose(win.current)
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Home) { win.current = -1; win.step(1); }
            else if (event.key === Qt.Key_End) { win.current = -1; win.step(-1); }
            else return;
            event.accepted = true;
        }
    }
    function step(d) {
        let i = current < 0 && d < 0 ? items.length : current;
        for (let n = 0; n < items.length; n++) {
            i = (i + d + items.length) % items.length;
            if (!items[i].rule) { current = i; return; }
        }
    }

    // Opens above the cursor, kept on screen; the shadow has room around it.
    readonly property real pad: 24
    Develop {
        id: page
        x: Math.max(8 - win.pad, Math.min(win.width - sheet.width - 8 - win.pad, win.at.x - win.pad))
        y: Math.max(8 - win.pad, win.at.y - sheet.height - 6 - win.pad) + (win.open ? 0 : 6)
        Behavior on y { enabled: !win.open; Ease { duration: 160 } }
        width: sheet.width + win.pad * 2
        height: sheet.height + win.pad * 2
        grain: 1

        Sheet {
            id: sheet
            x: win.pad; y: win.pad
            width: Math.min(300, Math.max(220, column.implicitWidth + 12))
            height: column.implicitHeight + 12
            radius: Theme.rM
            color: Theme.sheetStrong

            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }
            ColumnLayout {
                id: column
                x: 6; y: 6
                width: parent.width - 12
                spacing: 0
                Cap {
                    visible: win.title !== ""
                    text: win.title
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.leftMargin: 10; Layout.rightMargin: 10
                    Layout.topMargin: 4; Layout.bottomMargin: 4
                }
                Repeater {
                    model: win.items
                    Item {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool hot: win.current === index && !modelData.rule
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        implicitWidth: modelData.rule ? 0 : label.implicitWidth + 20
                        implicitHeight: modelData.rule ? 11 : 32
                        Rectangle {
                            visible: !!row.modelData.rule
                            anchors.centerIn: parent
                            width: parent.width - 12; height: 1
                            color: Theme.rule
                        }
                        Rectangle {
                            visible: !row.modelData.rule
                            anchors.fill: parent
                            radius: Theme.inner(Theme.rM, 6)
                            color: row.hot ? (row.modelData.danger ? Theme.error : Theme.ink) : "transparent"
                        }
                        Label {
                            id: label
                            visible: !row.modelData.rule
                            x: 10
                            width: parent.width - 20
                            height: parent.height
                            text: row.modelData.label || ""
                            color: row.hot ? Theme.inkText : row.modelData.danger ? Theme.error : Theme.text
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !row.modelData.rule
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: win.current = row.index
                            onExited: if (win.current === row.index) win.current = -1
                            onClicked: win.choose(row.index)
                        }
                    }
                }
            }
        }
    }
}
