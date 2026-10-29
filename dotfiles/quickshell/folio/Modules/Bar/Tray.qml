import QtQuick
import QtQuick.Layouts
import Quickshell
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
