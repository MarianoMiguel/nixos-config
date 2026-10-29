import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// Quick tiles, two columns: Wi-Fi, Bluetooth, Focus, VPN, Keep awake and
// Night light (when there is a tool for it). Wi-Fi and Bluetooth open their
// lists inline, under the tiles.
ColumnLayout {
    id: root
    required property var feed
    property string open: ""            // "wifi" | "bluetooth" | ""
    spacing: 8

    function show(which) { open = which; if (which === "wifi") rescan(); }
    function rescan() { feed.scan(); scanning.restart(); }
    Timer { id: scanning; interval: 6000 }
    function toggle(which) { show(open === which ? "" : which); }
    readonly property string focusUntil: feed.focusActive ? Qt.formatTime(new Date(feed.focusEnds), "HH:mm") : ""

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 8
        rowSpacing: 8
        uniformCellWidths: true

        SideTile {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            icon: "wifi"
            title: "Wi-Fi"
            on: root.feed.wifi.on
            sub: !root.feed.wifi.on ? "Off" : root.feed.wifi.ssid || (root.feed.wifi.wired ? "Ethernet" : "Not connected")
            expandable: true
            expanded: root.open === "wifi"
            onClicked: root.feed.setWifi(!root.feed.wifi.on)
            onExpand: root.toggle("wifi")
        }
        SideTile {
            visible: root.feed.bt.available
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            icon: "bluetooth"
            title: "Bluetooth"
            on: root.feed.bt.on
            sub: root.feed.bt.on ? root.feed.bt.summary : "Off"
            expandable: true
            expanded: root.open === "bluetooth"
            onClicked: root.feed.setBt(!root.feed.bt.on)
            onExpand: root.toggle("bluetooth")
        }
        SideTile {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            icon: "moon"
            title: "Focus"
            on: root.feed.focusActive
            sub: on ? "On · until " + root.focusUntil : "Off"
            onClicked: root.feed.toggleFocus()
        }
        SideTile {
            visible: root.feed.vpn.available
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            icon: "shield"
            title: "VPN"
            on: root.feed.vpn.on
            readOnly: !root.feed.vpn.canToggle
            sub: root.feed.vpn.on ? "Tailscale · " + root.feed.vpn.summary : root.feed.vpn.summary
            onClicked: if (!readOnly && !root.feed.vpn.busy) root.feed.setVpn(!root.feed.vpn.on)
        }
        SideTile {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            icon: "cup"
            title: "Keep awake"
            on: root.feed.awake
            sub: on ? "Screen stays on" : "Off"
            onClicked: root.feed.toggleAwake()
        }
        SideTile {
            visible: root.feed.night.available
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            icon: "sun"
            title: "Night light"
            on: root.feed.night.on
            sub: on ? "Warm" : "Off"
            onClicked: root.feed.toggleNight()
        }
    }

    // The open list, sprung open and closed.
    Item {
        id: drawer
        property real h: root.open !== "" ? body.implicitHeight : 0
        Behavior on h { SpringPanel {} }
        Layout.fillWidth: true
        Layout.preferredHeight: h
        visible: h > 0.5
        clip: true
        opacity: Math.min(1, h / 40)

        SideCard {
            id: body
            width: parent.width
            implicitHeight: list.implicitHeight + 12
            ColumnLayout {
                id: list
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.preferredHeight: 30
                    Cap { text: root.open === "bluetooth" ? "Devices" : "Networks"; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                    SideButton {
                        visible: root.open === "wifi" && root.feed.wifi.on
                        kind: "ghost"; round: true; size: 26; iconSize: 15; icon: "reload"
                        onClicked: root.rescan()
                    }
                }

                // Wi-Fi
                Repeater {
                    model: root.open === "wifi" && root.feed.wifi.on ? root.feed.wifi.networks.slice(0, 8) : []
                    SideTap {
                        id: net
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: Theme.inner(Theme.inner(26, 14), 6)
                        sink: false
                        onClicked: if (!modelData.active) root.feed.join(modelData.ssid)
                        Rectangle { anchors.fill: parent; radius: parent.radius; color: net.hovered ? Theme.well : "transparent" }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10
                            Icon { name: "wifi"; size: 16; color: net.modelData.active ? Theme.ink : Theme.text2; opacity: net.modelData.signal > 55 ? 1 : net.modelData.signal > 30 ? 0.7 : 0.45 }
                            Label { text: net.modelData.ssid; font.weight: net.modelData.active ? Font.DemiBold : Font.Normal; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                            Icon { visible: net.modelData.secure; name: "lock"; size: 14; color: Theme.text3 }
                            Icon { visible: net.modelData.active; name: "check"; size: 16; color: Theme.ink }
                        }
                    }
                }
                // Bluetooth
                Repeater {
                    model: root.open === "bluetooth" && root.feed.bt.on ? root.feed.bt.devices : []
                    SideTap {
                        id: dev
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: Theme.inner(Theme.inner(26, 14), 6)
                        sink: false
                        onClicked: if (!modelData.busy) root.feed.toggleDevice(modelData)
                        Rectangle { anchors.fill: parent; radius: parent.radius; color: dev.hovered ? Theme.well : "transparent" }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10
                            Icon { name: "bluetooth"; size: 16; color: dev.modelData.connected ? Theme.ink : Theme.text2 }
                            Label { text: dev.modelData.name; font.weight: dev.modelData.connected ? Font.DemiBold : Font.Normal; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                            Cap {
                                text: dev.modelData.busy ? "…" : dev.modelData.connected ? (dev.modelData.battery >= 0 ? Math.round(dev.modelData.battery * 100) + "%" : "On") : "Connect"
                                color: dev.modelData.connected ? Theme.ink : Theme.text3
                            }
                        }
                    }
                }
                // Off or nothing found
                RowLayout {
                    readonly property bool off: root.open === "wifi" ? !root.feed.wifi.on : !root.feed.bt.on
                    readonly property bool none: root.open === "wifi" ? root.feed.wifi.networks.length === 0 : root.feed.bt.devices.length === 0
                    visible: root.open !== "" && (off || none)
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    Layout.leftMargin: 8
                    Layout.rightMargin: 4
                    spacing: 10
                    Label {
                        text: parent.off ? (root.open === "wifi" ? "Wi-Fi is off" : "Bluetooth is off") : (root.open === "wifi" ? (scanning.running ? "Looking for networks…" : "No networks found") : "No paired devices")
                        color: Theme.text2
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                    }
                    SideButton {
                        visible: parent.off
                        text: "Turn on"; size: 28; fontSize: Theme.fsS
                        onClicked: root.open === "wifi" ? root.feed.setWifi(true) : root.feed.setBt(true)
                    }
                }
            }
        }
    }
}
