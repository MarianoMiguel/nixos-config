import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// Bluetooth: on and off; paired devices with their kind and battery,
// connect, disconnect and forget (with undo); nearby devices found while the
// page is open, and pairing them, with the passkey to confirm or type when
// the device asks for one.
SettingsPage {
    id: page
    title: "Bluetooth"
    description: "Headphones, mice, keyboards and phones. Paired devices reconnect on their own."

    readonly property var paired: Bluetooth.items.filter(i => i.paired && !Bluetooth.forgetting[i.address])
        .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
    readonly property var nearby: Bluetooth.items.filter(i => !i.paired && !i.unnamed)
        .sort((a, b) => a.name.localeCompare(b.name))
    readonly property var pairing: Bluetooth.pairing
    readonly property bool pairBusy: !!pairing && pairing.step !== "failed"
    property string pin: ""

    // Look for devices while the page is open (and Bluetooth is on), for two minutes at a time.
    function search() { if (Bluetooth.on) { Bluetooth.setDiscovering(true); searchClock.restart(); } }
    Timer { id: searchClock; interval: 120000; onTriggered: Bluetooth.setDiscovering(false) }
    Connections { target: Bluetooth; function onOnChanged() { if (Bluetooth.on) page.search(); } }
    Component.onCompleted: search()
    Component.onDestruction: { if (Bluetooth.pairing && Bluetooth.pairing.step === "failed") Bluetooth.dismissPair(); Bluetooth.setDiscovering(false); }

    function percent(b) { return Math.round(b * 100) + "%"; }
    function status(i) {
        if (i.busy) return i.connected ? "Disconnecting…" : "Connecting…";
        const parts = [i.kind, i.connected ? "Connected" : "Not connected"];
        return parts.join(" · ");
    }

    Notice { visible: !Bluetooth.available; icon: "bluetooth"; text: "No Bluetooth adapter found."; Layout.topMargin: 18 }

    Card {
        visible: Bluetooth.available
        Layout.topMargin: 18
        SettingRow {
            icon: "bluetooth"
            label: "Bluetooth"
            hint: Bluetooth.blocked ? "Blocked by a hardware switch or the firmware" : Bluetooth.switching ? "Switching…"
                : Bluetooth.on ? (Bluetooth.name ? "On · this laptop shows up as “" + Bluetooth.name + "”" : "On") : "Off"
            Toggle {
                checked: Bluetooth.on
                enabled: !Bluetooth.blocked && !Bluetooth.switching
                opacity: enabled ? 1 : 0.45
                onToggled: v => Bluetooth.setOn(v)
            }
        }
    }

    Notice {
        visible: Bluetooth.available && !Bluetooth.on
        icon: "bluetooth"
        text: Bluetooth.blocked ? "Bluetooth is blocked by a hardware switch or the firmware; turn it on there first." : "Bluetooth is off. Paired devices stay paired and reconnect when it is back on."
        action: Bluetooth.blocked ? "" : "Turn on"
        onActed: Bluetooth.setOn(true)
        Layout.topMargin: 10
    }

    // ------------------------------------------------------------- My devices

    Section { visible: Bluetooth.on; title: "My devices"; hint: "Click one to connect or disconnect it."; Component.onCompleted: page.mark("devices", this) }
    Notice { visible: Bluetooth.on && page.paired.length === 0; icon: "bluetooth"; text: "No paired devices yet. Pair one below and it shows up here." }
    Card {
        visible: Bluetooth.on && page.paired.length > 0
        divided: true
        Repeater {
            model: page.paired
            NetworkRow {
                id: dev
                required property var modelData
                readonly property var d: modelData
                icon: d.glyph
                selected: d.connected
                busy: d.busy
                title: d.name
                subtitle: page.status(d)
                clickable: !d.busy
                onClicked: Bluetooth.toggle(d)
                RowLayout {
                    spacing: 8
                    // Battery, when BlueZ reports it.
                    Rectangle {
                        visible: dev.d.connected && dev.d.battery >= 0
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: batt.implicitWidth + 16
                        radius: Theme.rXs
                        color: Theme.well
                        border.color: Theme.rule
                        RowLayout {
                            id: batt
                            anchors.centerIn: parent
                            spacing: 4
                            Icon { name: "battery"; size: 14; color: dev.d.battery < 0.2 ? Theme.warning : Theme.text2 }
                            Label { text: page.percent(dev.d.battery); font.pixelSize: Theme.fsS; font.family: Theme.mono; color: dev.d.battery < 0.2 ? Theme.warning : Theme.text2 }
                        }
                    }
                    Button { text: dev.d.connected ? "Disconnect" : "Connect"; enabled: !dev.d.busy; onClicked: Bluetooth.toggle(dev.d) }
                    Button { text: "Forget"; enabled: !dev.d.busy; onClicked: Bluetooth.forget(dev.d) }
                }
            }
        }
    }

    // ---------------------------------------------------------------- Nearby

    RowLayout {
        visible: Bluetooth.on
        Layout.fillWidth: true
        spacing: 10
        Section { title: "Nearby devices"; hint: "Put a device in pairing mode and it appears here."; Layout.fillWidth: true; Layout.minimumWidth: 0 }
        Button {
            Layout.alignment: Qt.AlignBottom
            Layout.bottomMargin: 10
            text: Bluetooth.discovering ? "Searching" : "Search"
            icon: "search"
            busy: Bluetooth.discovering
            onClicked: page.search()
        }
    }
    Notice {
        visible: Bluetooth.on && page.nearby.length === 0
        icon: Bluetooth.discovering ? "search" : "bluetooth"
        text: Bluetooth.discovering ? "Looking for devices in pairing mode…" : "No devices found. Put one in pairing mode and search again."
    }
    Card {
        visible: Bluetooth.on && page.nearby.length > 0
        divided: true
        Repeater {
            model: page.nearby
            NetworkRow {
                id: near
                required property var modelData
                readonly property var d: modelData
                readonly property bool mine: !!page.pairing && page.pairing.address === d.address
                icon: d.glyph
                title: d.name
                subtitle: mine ? (page.pairing.step === "failed" ? "Not paired" : "Pairing…") : d.kind
                busy: mine && page.pairing.step !== "failed" && page.pairing.step !== "confirm" && page.pairing.step !== "display" && page.pairing.step !== "pin"
                open: mine
                clickable: !page.pairBusy && !mine
                panel: pairPanel
                onClicked: Bluetooth.pair(d)
                Button { visible: !near.mine; text: "Pair"; enabled: !page.pairBusy; onClicked: Bluetooth.pair(near.d) }
            }
        }
    }

    // Pairing, step by step: a code to compare or type, a PIN, or why it failed.
    Component {
        id: pairPanel
        ColumnLayout {
            id: pp
            readonly property var p: page.pairing || ({ "step": "", "name": "", "passkey": "", "text": "" })
            readonly property string code: p.passkey ? String(p.passkey).replace(/^(\d{3})(\d{3})$/, "$1 $2") : ""
            spacing: 8
            Text {
                text: ({
                    "working": "Pairing with “" + pp.p.name + "”. Accept on the device if it asks.",
                    "confirm": "Check that “" + pp.p.name + "” shows this code, then confirm.",
                    "display": "Type this code on “" + pp.p.name + "”, then press Enter.",
                    "pin": "Type the PIN for “" + pp.p.name + "” (often 0000 or 1234).",
                    "connecting": "Paired. Connecting…",
                    "failed": pp.p.text
                })[pp.p.step] || ""
                color: pp.p.step === "failed" ? Theme.error : Theme.text2
                font.family: Theme.ui; font.pixelSize: Theme.fsS
                wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                visible: pp.code !== "" && (pp.p.step === "confirm" || pp.p.step === "display")
                text: pp.code
                color: Theme.ink
                font.family: Theme.mono; font.pixelSize: 28; font.weight: Font.DemiBold; font.letterSpacing: 3
            }
            Field {
                id: pinField
                visible: pp.p.step === "pin"
                Layout.fillWidth: true
                icon: "lock"; placeholder: "PIN"
                onTextChanged: page.pin = text
                onAccepted: Bluetooth.enterPin(text)
                onVisibleChanged: if (visible) { text = page.pin; focusNow(); }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Button { visible: pp.p.step === "confirm"; text: "Confirm"; primary: true; onClicked: Bluetooth.confirmPair(true) }
                Button { visible: pp.p.step === "pin"; text: "Pair"; primary: true; enabled: pinField.text.length > 0; onClicked: Bluetooth.enterPin(pinField.text) }
                Button {
                    visible: pp.p.step === "failed"; text: "Try again"; primary: true
                    onClicked: { const it = page.nearby.find(i => i.address === pp.p.address); Bluetooth.dismissPair(); if (it) Bluetooth.pair(it); }
                }
                Button { visible: pp.p.step !== "failed"; text: "Cancel"; onClicked: pp.p.step === "confirm" ? Bluetooth.confirmPair(false) : Bluetooth.cancelPair() }
                Button { visible: pp.p.step === "failed"; text: "Dismiss"; onClicked: Bluetooth.dismissPair() }
                Item { Layout.fillWidth: true }
            }
        }
    }
}
