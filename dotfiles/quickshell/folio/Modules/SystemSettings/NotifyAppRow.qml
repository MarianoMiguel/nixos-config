import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// One app that has notified: its icon, name and what its notifications do,
// and a switch that allows them or turns them off. Open, it shows whether
// they peek as banners and play a sound; it opens and closes on a spring.
Item {
    id: root
    property var app: ({})              // { key, name, icon, allow, banners, sound, seen }
    property bool expanded: false
    property bool first: false
    signal toggled()
    signal changed(string field, bool value)

    readonly property bool open: expanded && app.allow
    readonly property string summary: {
        if (!app.allow) return "Off";
        const what = app.banners && app.sound ? "Banners and sound" : app.banners ? "Banners, silent"
            : app.sound ? "Sound, in the sidebar" : "In the sidebar only";
        const when = Notifs.since(app.seen);
        return !when ? what : what + " · " + (when === "just now" ? when : "last " + when);
    }

    Layout.fillWidth: true
    implicitHeight: head.height + (open ? body.implicitHeight + 6 : 0)
    clip: true
    Behavior on implicitHeight { SpringPanel {} }

    Rectangle { visible: !root.first; x: 14; width: root.width - 28; height: 1; color: Theme.rule }

    Item {
        id: head
        width: root.width
        height: Math.max(56, text.implicitHeight + 20)
        Rectangle {
            anchors.fill: parent; anchors.margins: 3
            radius: Theme.inner(Theme.rM, 3)
            color: area.containsMouse && root.app.allow ? Theme.wellStrong : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.tQuick } }
        }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
            AppsIcon {
                icon: root.app.icon || ""; name: root.app.name || ""; size: 30
                opacity: root.app.allow ? 1 : 0.5
            }
            ColumnLayout {
                id: text
                Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 1
                Label { text: root.app.name || ""; font.weight: Font.Medium; Layout.fillWidth: true; Layout.minimumWidth: 0; opacity: root.app.allow ? 1 : 0.6 }
                Label { text: root.summary; color: Theme.text2; font.pixelSize: Theme.fsS; Layout.fillWidth: true; Layout.minimumWidth: 0 }
            }
            Icon {
                name: "down"; size: 16; color: Theme.text3
                opacity: root.app.allow ? 1 : 0
                rotation: root.open ? 180 : 0
                Behavior on rotation { SpringPress {} }
                Behavior on opacity { SpringSoft {} }
            }
            Toggle { checked: !!root.app.allow; onToggled: v => root.changed("allow", v) }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            z: -1
            hoverEnabled: true
            enabled: !!root.app.allow
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled()
        }
    }

    ColumnLayout {
        id: body
        y: head.height
        width: root.width
        spacing: 0
        opacity: root.open ? 1 : 0
        Behavior on opacity { SpringSoft {} }
        Option { label: "Banners"; hint: "Peek from the island when they arrive."; field: "banners" }
        Option { label: "Sound"; hint: "A soft chime, unless the app asks for silence."; field: "sound" }
    }

    component Option: Item {
        id: opt
        property string label
        property string hint
        property string field
        Layout.fillWidth: true
        implicitHeight: Math.max(46, words.implicitHeight + 14)
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 56; anchors.rightMargin: 14; spacing: 12
            ColumnLayout {
                id: words
                Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 0
                Label { text: opt.label; font.pixelSize: Theme.fsS + 0.5; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                Label { text: opt.hint; color: Theme.text2; font.pixelSize: Theme.fsS - 0.5; Layout.fillWidth: true; Layout.minimumWidth: 0 }
            }
            Toggle { checked: !!root.app[opt.field]; onToggled: v => root.changed(opt.field, v) }
        }
    }
}
