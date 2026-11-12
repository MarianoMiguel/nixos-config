import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Common
import qs.Widgets

// The system tray: 16 px icons as the apps ship them. Click activates (or
// opens the menu of menu-only items), right-click opens the menu in Folio's
// own sheet, middle-click is the secondary action, the wheel scrolls.
Item {
    id: root

    property var bar
    property var fake: []          // fixture: Folio icon names standing in for apps

    readonly property var items: SystemTray.items.values.filter(i => i.status !== Status.Passive)
    implicitWidth: row.implicitWidth
    Layout.preferredWidth: row.implicitWidth
    visible: implicitWidth > 0

    // An SNI icon name to an image source; "name?path=dir" means a file there.
    function source(item) {
        const icon = item ? item.icon : "";
        if (!icon) return "";
        if (icon.indexOf("?path=") >= 0) {
            const [name, path] = icon.split("?path=");
            return "file://" + path + "/" + name.slice(name.lastIndexOf("/") + 1);
        }
        return icon.startsWith("/") ? "file://" + icon : icon;
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
            model: root.items
            Slot {
                id: slot
                required property var modelData
                active: menu.visible && menu.anchorItem === slot
                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 16
                    source: root.source(slot.modelData)
                }
                onClicked: mouse => {
                    const item = slot.modelData;
                    if (mouse.button === Qt.MiddleButton) item.secondaryActivate();
                    else if (mouse.button === Qt.RightButton || item.onlyMenu) { if (item.hasMenu) menu.show(item, slot); }
                    else item.activate();
                }
                onWheel: (delta, horizontal) => slot.modelData.scroll(delta, horizontal)
            }
        }
        Repeater {
            model: root.fake
            Slot {
                required property string modelData
                Icon { anchors.centerIn: parent; name: parent.modelData; size: 16 }
            }
        }
    }

    TrayMenu { id: menu; bar: root.bar }

    // Tests (the harness has no tray apps): `tray menu normal|stress|empty`
    // opens a made-up menu in TrayMenu, anything else closes it; `tray
    // chosen` is the last entry it ran. One bar answers: the first screen's.
    function entry(text, more) {
        return Object.assign({ "text": text, "enabled": true, "isSeparator": false, "hasChildren": false, "buttonType": 0, "checkState": 0, "icon": "",
                               "children": [], "triggered": () => {} }, more || {});
    }
    function sub(text, children) { return entry(text, { "hasChildren": true, "children": children }); }
    readonly property var sep: entry("", { "isSeparator": true })
    function fixtureMenu(name) {
        if (name === "normal") return [
            entry("Open Signal"), sep,
            entry("Show notifications", { "buttonType": 1, "checkState": Qt.Checked }),
            sub("Status", [entry("Available", { "buttonType": 2, "checkState": Qt.Checked }), entry("Away", { "buttonType": 2 }), entry("Do not disturb", { "buttonType": 2 })]),
            entry("Check for updates", { "enabled": false }), sep,
            entry("Quit")
        ];
        if (name === "stress") {
            const many = [];
            for (let i = 1; i <= 24; i++) many.push(entry("Recent conversation number " + i + " with a name long enough to need eliding at the edge"));
            return [
                sub("Accounts", [sub("work@example.com — Payments Reconciliation Console (staging, eu-west-1)", [entry("Sign out"), entry("Switch to this account")]), entry("personal@example.com")]),
                sub("Recent", many), sep,
                entry("A very long action label that runs well past the width a tray menu allows itself"),
                entry("Disabled", { "enabled": false }), sep, entry("Quit")
            ];
        }
        if (name === "empty") return [];
        return null;
    }
    function openFixture(name) {
        const list = fixtureMenu(name);
        if (list) menu.showFixture(list, root); else menu.close();
    }
    function chosenFixture() { return menu.lastChosen; }
    LazyLoader {
        active: !!root.bar && root.bar.screen === Quickshell.screens[0]
        IpcHandler {
            target: "tray"
            function menu(name: string): void { root.openFixture(name); }
            function chosen(): string { return root.chosenFixture(); }
        }
    }

    component Slot: Rectangle {
        id: s
        signal clicked(var mouse)
        signal wheel(int delta, bool horizontal)
        property bool active: false
        width: 26; height: 26
        radius: Theme.rS
        color: area.containsMouse || active ? Theme.well : Theme.rgba(Theme.ink, 0)
        Behavior on color { ColorAnimation { duration: Theme.tQuick } }
        scale: area.pressed ? 0.92 : 1
        Behavior on scale { SpringPress {} }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => s.clicked(mouse)
            onWheel: event => {
                const v = event.angleDelta.y !== 0;
                s.wheel(v ? event.angleDelta.y : event.angleDelta.x, !v);
            }
        }
    }
}
