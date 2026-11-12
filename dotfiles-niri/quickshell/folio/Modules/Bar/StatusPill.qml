import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// The status pill: network, Bluetooth, sound and battery at a glance. Opens
// the sidebar. The battery turns to the error tone when it runs low.
Rectangle {
    id: root

    property var fx: null

    readonly property bool online: fx ? fx.online : Network.online
    readonly property bool wired: fx ? fx.wired : (Network.wired && !Network.ssid)
    readonly property bool btShown: fx ? fx.bluetooth : (Bluetooth.available && Bluetooth.on)
    readonly property bool btConnected: fx ? fx.btConnected : Bluetooth.connected.length > 0
    readonly property bool muted: fx ? fx.muted : (Audio.muted || !Audio.sink)
    readonly property bool battery: fx ? fx.battery : Battery.present
    readonly property int percent: fx ? fx.percent : Battery.percent
    readonly property bool charging: fx ? fx.charging : (Battery.charging || Battery.full)
    readonly property bool low: fx ? fx.low : Battery.low

    Layout.preferredWidth: row.implicitWidth + 20
    Layout.preferredHeight: 26
    radius: Theme.rS
    color: area.containsMouse || Shell.sidebarOpen ? Theme.well : Theme.rgba(Theme.ink, 0)
    Behavior on color { ColorAnimation { duration: Theme.tQuick } }
    scale: area.pressed ? 0.95 : 1
    Behavior on scale { SpringPress {} }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 9
        Icon { name: root.wired ? "globe" : "wifi"; size: 16; opacity: root.online ? 1 : 0.4; anchors.verticalCenter: parent.verticalCenter }
        Icon { visible: root.btShown; name: "bluetooth"; size: 16; opacity: root.btConnected ? 1 : 0.55; anchors.verticalCenter: parent.verticalCenter }
        Icon { name: root.muted ? "mute" : "speaker"; size: 16; anchors.verticalCenter: parent.verticalCenter }
        Row {
            visible: root.battery
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter
            Icon {
                name: root.charging ? "bolt" : "battery"
                size: 16
                color: root.low ? Theme.error : Theme.text
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                text: root.percent + "%"
                font.weight: Font.Medium
                font.features: { "tnum": 1 }
                color: root.low ? Theme.error : Theme.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Shell.toggleSidebar()
    }
}
