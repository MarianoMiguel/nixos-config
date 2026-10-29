import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// The page's foot: battery, then Settings, Lock and Power (a small menu).
RowLayout {
    id: root
    required property var feed
    property alias powerButton: power
    property bool powerOpen: false
    signal powerClicked()
    spacing: 8

    readonly property var b: feed.battery

    RowLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.leftMargin: 4
        spacing: 8
        visible: root.b.present
        Icon { name: root.b.charging ? "bolt" : "battery"; size: 18; color: root.b.low ? Theme.error : Theme.text2 }
        Label {
            text: root.b.percent + "%" + (root.b.label ? " · " + root.b.label : "")
            color: root.b.low ? Theme.error : Theme.text2
            font.pixelSize: Theme.fsS - 0.5
            Layout.fillWidth: true
            Layout.minimumWidth: 0
        }
    }
    Item { visible: !root.b.present; Layout.fillWidth: true }
    SideButton { size: 36; implicitWidth: 36; radius: Theme.inner(26, 14); icon: "gear"; onClicked: Shell.openSettings("") }
    SideButton { size: 36; implicitWidth: 36; radius: Theme.inner(26, 14); icon: "lock"; onClicked: root.feed.lock() }
    SideButton {
        id: power
        size: 36; implicitWidth: 36; radius: Theme.inner(26, 14); icon: "power"
        kind: root.powerOpen ? "ink" : "well"
        onClicked: root.powerClicked()
    }
}
