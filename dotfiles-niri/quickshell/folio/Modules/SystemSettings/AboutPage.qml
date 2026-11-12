import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// About: this computer and the software it runs, read once per visit
// (Services/About), and a plain-text summary for bug reports and chats.
// The device name is NixOS's (networking.hostName), so it is shown, not
// edited. Fixtures: about fixture normal|stress|empty.
SettingsPage {
    id: page
    title: "About"
    description: "This computer, and the software it runs."

    readonly property var i: About.info
    property real now: Date.now()
    Timer { interval: 30000; repeat: true; running: true; onTriggered: page.now = Date.now() }
    Component.onCompleted: { About.refresh(); Battery.refresh(); }

    readonly property bool laptop: i.chassis === "laptop" || i.chassis === "convertible" || i.chassis === "tablet"
    readonly property var disk: i.disk || {}
    readonly property real diskUse: disk.size > 0 ? disk.used / disk.size : 0

    // ------------------------------------------------------------ the device

    Item { Layout.preferredHeight: 14 }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: hero.implicitHeight + 40
        radius: Theme.rM
        color: Theme.well
        border.color: Theme.rule

        RowLayout {
            id: hero
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 20 }
            spacing: 18
            Rectangle {
                Layout.preferredWidth: 64; Layout.preferredHeight: 64; radius: 18
                Layout.alignment: Qt.AlignTop
                color: Theme.ink
                Icon { anchors.centerIn: parent; name: page.laptop ? "laptop" : "display"; size: 32; color: Theme.inkText }
            }
            ColumnLayout {
                Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                Cap { text: page.i.prettyName ? "Device name · " + page.i.prettyName : "Device name"; Layout.fillWidth: true }
                Text {
                    text: page.i.hostname || "Unnamed"
                    color: page.i.hostname ? Theme.ink : Theme.text3
                    font.family: Theme.hero; font.weight: Theme.heroWeight; font.pixelSize: 46
                    elide: Text.ElideRight; maximumLineCount: 1
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                }
                Label {
                    text: About.model || "Unknown model"
                    color: About.model ? Theme.text : Theme.text3
                    font.pixelSize: Theme.fsL; font.weight: Font.Medium
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                }
                Label {
                    text: [About.nixos, page.i.generation && page.i.generation.number > 0 ? "generation " + page.i.generation.number : ""].filter(x => x).join(" · ") || "NixOS version unknown"
                    color: Theme.text2; font.pixelSize: Theme.fsS
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                }
                // The system and its theme.
                RowLayout {
                    Layout.topMargin: 6; spacing: 7
                    Mark { Layout.preferredWidth: 18; Layout.preferredHeight: 18; color: Theme.ink }
                    Label { text: "Interstellar · " + (Theme.lumen ? "Lumen" : "Folio"); font.weight: Font.DemiBold; font.pixelSize: Theme.fsS }
                }
            }
            Button {
                Layout.alignment: Qt.AlignTop
                text: "Copy summary"; icon: "note"
                onClicked: About.copy()
            }
        }
    }
    Text {
        text: "The name is set by NixOS (networking.hostName); change it there and rebuild."
        color: Theme.text3; font.family: Theme.ui; font.pixelSize: Theme.fsS
        wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
        Layout.fillWidth: true; Layout.topMargin: 8
    }

    // ------------------------------------------------------------ hardware

    Section { title: "Hardware"; Component.onCompleted: page.mark("hardware", this) }
    Card {
        divided: true
        AboutRow { label: "Processor"; value: About.processor; hint: About.processorLine }
        AboutRow { label: "Memory"; value: About.memory; hint: About.memoryLine }
        Repeater {
            model: (page.i.gpus || []).length ? page.i.gpus : [{ "name": "", "vram": 0 }]
            AboutRow {
                required property var modelData
                required property int index
                label: index === 0 ? "Graphics" : ""
                value: modelData.name
                hint: modelData.vram > 0 ? About.gib(modelData.vram) + (page.laptop ? " of memory, shared" : " of video memory") : ""
            }
        }
        AboutRow {
            label: "Storage"
            value: About.diskLine
            hint: page.disk.avail > 0 ? About.size(page.disk.avail) + " free on " + (page.disk.mount || "/") + (page.diskUse > 0.9 ? ": nearly full" : "") : ""
            valueColor: page.diskUse > 0.9 ? Theme.warning : Theme.text
            showExtra: page.disk.size > 0
            Rectangle {
                width: 220; height: 6; radius: 3
                color: Theme.wellStrong
                Rectangle {
                    height: parent.height; radius: 3
                    width: Math.max(height, parent.width * page.diskUse)
                    color: page.diskUse > 0.9 ? Theme.warning : Theme.ink
                    Behavior on width { SpringPanel {} }
                }
            }
        }
        AboutRow {
            label: "Firmware"
            value: page.i.firmware && page.i.firmware.version ? [page.i.firmware.vendor, page.i.firmware.version].filter(x => x).join(" ") : ""
            hint: page.i.firmware && page.i.firmware.date > 0 ? "Released " + Qt.formatDate(new Date(page.i.firmware.date), "d MMM yyyy") : ""
        }
        AboutRow {
            visible: !!About.battery.present
            label: "Battery"
            value: { const h = Battery.health(About.battery); return h > 0 ? h + "% of its original capacity" : About.battery.percent + "%"; }
            hint: About.battery.cycles > 0 ? About.battery.cycles + " charge cycles" : ""
        }
    }

    // ------------------------------------------------------------ software

    Section { title: "Software"; Component.onCompleted: page.mark("software", this) }
    Card {
        divided: true
        AboutRow {
            label: "NixOS"
            value: (page.i.nixos || {}).version || ""
            hint: (page.i.nixos || {}).codename ? page.i.nixos.codename + ((page.i.nixos || {}).revision ? " · nixpkgs " + page.i.nixos.revision : "") : ""
        }
        AboutRow {
            label: "Generation"
            value: page.i.generation && page.i.generation.number > 0 ? String(page.i.generation.number) : ""
            hint: page.i.generation && page.i.generation.time > 0 ? "Built " + About.date(page.i.generation.time) + " · " + About.ago(page.i.generation.time) : ""
        }
        AboutRow { label: "Kernel"; value: page.i.kernel ? "Linux " + page.i.kernel : "" }
        AboutRow { label: "niri"; value: page.i.niri || "" }
        AboutRow {
            label: "Quickshell"
            value: (page.i.quickshell || {}).version || ""
            hint: (page.i.quickshell || {}).revision ? "revision " + page.i.quickshell.revision : ""
        }
        AboutRow {
            label: "Shell"
            value: About.shellName
            hint: About.shellLine
            valueColor: (page.i.shell || {}).choice === "dms" ? Theme.warning : Theme.text
        }
        AboutRow { label: "Uptime"; value: page.i.bootTime > 0 ? About.uptime(page.now - page.i.bootTime) : "" }
    }
}
