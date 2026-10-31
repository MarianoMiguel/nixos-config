import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Common

// A context menu: the dock's (an app's, the Trash's) and the desktop's. It
// prints in at the point it opens from, drifting 6 px out of it, and lifts
// back into it (Lumen fades). `instant` drops all of that: it appears and
// goes at once, in every theme and at every Motion setting (the dock's
// menu, used constantly: the owner's call, 2026-10-31). A transparent layer
// over the screen catches the click that closes it, so the window covers its
// screen; `at` is in screen coordinates.
//
//   ContextMenu { id: menu; screen: someScreen; side: "below" }
//   menu.popup(Qt.point(x, y), "Title", [
//       { "label": "Open", "icon": "folder", "run": () => … },
//       { "rule": true },
//       { "label": "Empty Trash", "detail": "42 items", "danger": true, "disabled": false, "run": () => … }])
//
// side "below" opens under and right of the point, flipping left or up to
// stay on screen (the desktop); "above" opens over it (the dock). A list
// taller than the screen scrolls. `icon` is a Folio icon name; `detail` a
// short caption at the end of the row (a shortcut, the next plate's name).
// The keyboard: Up and Down (from nothing lit, Down lights the first and
// Up the last; disabled rows are skipped), Home and End, Tab, a letter
// lights the next row starting with it, Return, Enter or Space choose,
// Escape closes. With nothing to choose it shows `emptyText`.
PanelWindow {
    id: win

    property var items: []
    property string title: ""
    property point at: Qt.point(0, 0)
    property string side: "below"
    property string layerName: "folio:menu"
    property string emptyText: "Nothing to do here"
    property real minWidth: 220
    property real maxWidth: 320
    property bool instant: false
    property bool open: false
    property int current: -1
    readonly property bool icons: shown.some(it => !!it.icon)
    readonly property var shown: items.some(it => !it.rule) ? items : [{ "label": emptyText, "disabled": true }]
    signal dismissed()
    signal chosen(int index, string label)

    // keyed: opened from the keyboard, so the first row is lit.
    function popup(pos, heading, list, keyed) {
        at = pos; title = heading || ""; items = list || []; current = -1;
        flick.contentY = 0;
        driftOn = false; drift = instant ? 0 : away(); driftOn = !instant;
        open = true;
        drift = 0;
        if (instant) page.progress = 1;
        else { page.progress = 0; page.printIn(240); }
        keys.forceActiveFocus();
        if (keyed) { KeyNav.key(); step(1); }
    }
    function close() {
        if (!open) return;
        open = false;
        if (!instant) { drift = away(); page.lift(160); }
        win.dismissed();
    }
    // The drift's start and end: toward the point the menu opened from.
    function away() { return up ? 6 : -6; }
    function usable(it) { return !!it && !it.rule && !it.disabled && typeof it.run === "function"; }
    function choose(i) {
        const it = shown[i];
        if (!usable(it)) return;
        close();
        win.chosen(i, it.label || "");
        it.run();
    }
    function step(d) {
        const n = shown.length;
        let i = current < 0 && d < 0 ? n : current;
        for (let k = 0; k < n; k++) {
            i = (i + d + n) % n;
            if (usable(shown[i])) { current = i; keepInView(); return; }
        }
    }
    // A letter lights the next row whose label starts with it.
    function jump(ch) {
        const n = shown.length, c = ch.toLowerCase();
        for (let k = 1; k <= n; k++) {
            const i = (Math.max(current, -1) + k + n) % n;
            if (usable(shown[i]) && String(shown[i].label || "").toLowerCase().charAt(0) === c) { current = i; keepInView(); return true; }
        }
        return false;
    }
    function keepInView() {
        const row = rows.itemAt(current);
        if (row && flick.interactive) flick.contentY = KeyNav.scrollFor(flick, row, 4);
    }

    visible: open || (!instant && page.running)
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: win.layerName
    WlrLayershell.keyboardFocus: win.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: win.open ? sheet : null; radius: Theme.rM + frost.extra }
    BlurNudge { id: frost; key: win.open + ":" + Math.round(sheet.height) }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: win.close()
    }

    Item {
        id: keys
        focus: true
        Keys.onPressed: event => {
            if (!win.open) return;
            KeyNav.key();
            const k = event.key;
            if (k === Qt.Key_Escape) win.close();
            else if (k === Qt.Key_Up || k === Qt.Key_Backtab) win.step(-1);
            else if (k === Qt.Key_Down || k === Qt.Key_Tab) win.step(1);
            else if (k === Qt.Key_Home) { win.current = -1; win.step(1); }
            else if (k === Qt.Key_End) { win.current = -1; win.step(-1); }
            else if (KeyNav.activates(event)) { if (!event.isAutoRepeat) win.choose(win.current); }
            else if (!(KeyNav.plain(event) && /^[A-Za-z0-9]$/.test(event.text) && win.jump(event.text))) return;
            event.accepted = true;
        }
    }

    // The sheet beside the point, kept 8 px inside the screen; the print
    // has room around it for the shadow.
    readonly property real pad: 24
    readonly property real margin: 8
    readonly property real sheetW: Math.min(maxWidth, Math.max(minWidth, column.implicitWidth + 12), width - margin * 2)
    readonly property real sheetH: Math.min(column.implicitHeight + 12, height - margin * 2)
    readonly property bool flipX: side === "below" && at.x + 2 + sheetW > width - margin
    readonly property bool up: side === "above" || at.y + 2 + sheetH > height - margin
    readonly property real sheetX: {
        const x = side === "above" ? at.x : flipX ? at.x - 2 - sheetW : at.x + 2;
        return Math.round(Math.max(margin, Math.min(width - sheetW - margin, x)));
    }
    readonly property real sheetY: {
        const y = up ? at.y - (side === "above" ? 6 : 2) - sheetH : at.y + 2;
        return Math.round(Math.max(margin, Math.min(height - sheetH - margin, y)));
    }
    property real drift: 0
    property bool driftOn: true
    Behavior on drift { enabled: win.driftOn; SpringSoft { epsilon: 0.05 } }
    Develop {
        id: page
        x: win.sheetX - win.pad
        y: win.sheetY - win.pad + win.drift
        width: sheet.width + win.pad * 2
        height: sheet.height + win.pad * 2
        grain: 1

        Sheet {
            id: sheet
            x: win.pad; y: win.pad
            width: win.sheetW
            height: win.sheetH
            radius: Theme.rM
            color: Theme.sheetStrong

            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }
            PointerWatch { }
            Flickable {
                id: flick
                x: 6; y: 6
                width: parent.width - 12
                height: parent.height - 12
                contentWidth: width
                contentHeight: column.implicitHeight
                interactive: contentHeight > height + 0.5
                clip: interactive
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: column
                    width: flick.width
                    spacing: 0
                    Cap {
                        visible: win.title !== ""
                        text: win.title
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.maximumWidth: win.maxWidth - 32
                        Layout.leftMargin: 10; Layout.rightMargin: 10
                        Layout.topMargin: 4; Layout.bottomMargin: 4
                    }
                    Repeater {
                        id: rows
                        model: win.shown
                        Item {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property bool rule: !!modelData.rule
                            readonly property bool off: !rule && !win.usable(modelData)
                            readonly property bool hot: win.current === index && !rule && !off
                            readonly property color fg: hot ? Theme.inkText : off ? Theme.text3 : modelData.danger ? Theme.error : Theme.text
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            implicitWidth: rule ? 0 : 20 + (win.icons ? 26 : 0) + label.implicitWidth + (detail.text ? 18 + detail.implicitWidth : 0)
                            implicitHeight: rule ? 11 : 32
                            Rectangle {
                                visible: row.rule
                                anchors.centerIn: parent
                                width: parent.width - 12; height: 1
                                color: Theme.rule
                            }
                            Rectangle {
                                visible: !row.rule
                                anchors.fill: parent
                                radius: Theme.inner(Theme.rM, 6)
                                color: row.hot ? (row.modelData.danger ? Theme.error : Theme.ink) : Theme.rgba(Theme.ink, 0)
                            }
                            Icon {
                                visible: !row.rule && win.icons && !!row.modelData.icon
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                name: row.modelData.icon || ""
                                size: 16
                                color: row.hot || row.off ? row.fg : row.modelData.danger ? Theme.error : Theme.text2
                            }
                            Label {
                                id: label
                                visible: !row.rule
                                x: 10 + (win.icons ? 26 : 0)
                                width: Math.max(0, parent.width - x - 10 - (detail.text ? detail.width + 14 : 0))
                                height: parent.height
                                text: row.rule ? "" : (row.modelData.label || "")
                                color: row.fg
                            }
                            Cap {
                                id: detail
                                visible: !row.rule && text !== ""
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, Math.round(row.width * 0.42))
                                text: row.rule ? "" : (row.modelData.detail || "")
                                color: row.hot ? Theme.rgba(Theme.inkText, 0.75) : Theme.text3
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: !row.rule
                                hoverEnabled: true
                                cursorShape: row.off ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onEntered: win.current = row.off ? -1 : row.index
                                onExited: if (win.current === row.index) win.current = -1
                                onClicked: win.choose(row.index)
                            }
                        }
                    }
                }
            }
        }
    }
}
