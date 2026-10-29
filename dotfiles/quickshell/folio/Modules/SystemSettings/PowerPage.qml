import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// Power & battery: the battery now and over the last day, its health and
// charge limit, the power mode, what the lid and idleness do, and what warns
// when the battery runs low. NixOS decides the lid and the low-battery action
// (shown, not changed); Folio decides the idle times (Lock & screensaver).
// Fixtures: power fixture normal|stress|empty (Services/Power).
SettingsPage {
    id: page
    title: "Power & battery"
    description: "The battery, how hard the computer works, and what it does when you close the lid or walk away."

    readonly property var b: Battery.info
    readonly property var m: Power.mode
    readonly property var p: Power.policy
    readonly property int health: Battery.health(b)
    readonly property bool limited: b.limit > 0 && b.limit < 100
    readonly property bool draining: b.present && b.onBattery && b.state !== "charging" && b.state !== "full" && b.state !== "pending"
    readonly property bool lowNow: draining && b.percent <= p.lowAt

    Component.onCompleted: { Battery.watch(1); Power.refresh(); }
    Component.onDestruction: Battery.watch(-1)

    function minutes(s) {
        if (!(s > 0)) return "Never";
        return s < 60 ? s + " s" : Math.round(s / 60) + " min";
    }

    // ------------------------------------------------------------ battery now

    Item { Layout.preferredHeight: 14 }
    Notice {
        visible: !page.b.present
        icon: "bolt"
        text: "This computer has no battery. It runs on mains power, so there is no charge, health or low-battery warning to show."
    }
    Rectangle {
        visible: page.b.present
        Layout.fillWidth: true
        implicitHeight: now.implicitHeight + 36
        radius: Theme.rM
        color: Theme.well
        border.color: Theme.rule

        ColumnLayout {
            id: now
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            spacing: 14

            RowLayout {
                Layout.fillWidth: true; spacing: 18
                ColumnLayout {
                    Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                    Cap { text: "Battery"; Layout.fillWidth: true }
                    RowLayout {
                        spacing: 8
                        Text {
                            text: page.b.percent + "%"
                            font.family: Theme.ui; font.pixelSize: 44; font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: page.lowNow ? Theme.error : Theme.text
                            Behavior on color { ColorAnimation { duration: Theme.tQuick } }
                        }
                        Icon {
                            visible: !page.b.onBattery
                            name: "bolt"; size: 22; color: Theme.ink
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                    Label {
                        text: Battery.stateLine(page.b) + (page.lowNow ? " · plug in soon" : "")
                        color: page.lowNow ? Theme.error : Theme.text2
                        Layout.fillWidth: true; Layout.minimumWidth: 0
                    }
                }
                // What it draws and holds.
                GridLayout {
                    columns: 2; columnSpacing: 14; rowSpacing: 4
                    Layout.alignment: Qt.AlignBottom
                    Cap { text: page.b.state === "charging" ? "Charging at" : "Drawing" }
                    Label { text: page.b.rate > 0.05 ? page.b.rate.toFixed(1) + " W" : "—"; font.features: { "tnum": 1 }; Layout.alignment: Qt.AlignRight }
                    Cap { text: "Holding" }
                    Label { text: page.b.energyFull > 0 ? page.b.energy.toFixed(1) + " of " + page.b.energyFull.toFixed(1) + " Wh" : "—"; font.features: { "tnum": 1 }; Layout.alignment: Qt.AlignRight }
                }
            }

            // The level, and the limit it stops at.
            Item {
                Layout.fillWidth: true
                implicitHeight: 10 + (page.limited ? 16 : 0)
                Cap {
                    visible: page.limited
                    text: "Stops at " + page.b.limit + "%"
                    x: Math.max(0, Math.min(parent.width - implicitWidth, parent.width * page.b.limit / 100 - implicitWidth / 2))
                }
                Rectangle {
                    id: track
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 10; radius: 5
                    color: Theme.wellStrong
                    Rectangle {
                        height: parent.height; radius: 5
                        width: Math.max(height, parent.width * Math.min(100, page.b.percent) / 100)
                        color: page.lowNow ? Theme.error : Theme.ink
                        Behavior on width { SpringPanel {} }
                        Behavior on color { ColorAnimation { duration: Theme.tQuick } }
                    }
                    Rectangle {
                        visible: page.limited
                        x: parent.width * page.b.limit / 100 - 1; y: -3
                        width: 2; height: parent.height + 6; radius: 1
                        color: Theme.text2
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.rule }
            PowerHistory {
                points: page.b.history
                level: page.b.percent
                plugged: !page.b.onBattery
            }
        }
    }

    // ------------------------------------------------------------ health

    Section {
        visible: page.b.present
        title: "Battery health"
        hint: "Batteries hold less as they age. Keeping this one below full while it stays plugged in slows that down."
        Component.onCompleted: page.mark("health", this)
    }
    Card {
        visible: page.b.present
        divided: true
        SettingRow {
            icon: "battery"
            label: "Maximum capacity"
            hint: page.health < 0 ? "The battery does not report its design capacity."
                : (page.health >= 80 ? "Normal. " : "Service recommended: it holds much less than when new. ")
                  + page.b.energyFull.toFixed(1) + " Wh now, " + page.b.energyDesign.toFixed(1) + " Wh when new."
            Label {
                text: page.health > 0 ? page.health + "%" : "—"
                font.pixelSize: Theme.fsL; font.weight: Font.DemiBold; font.features: { "tnum": 1 }
                color: page.health > 0 && page.health < 80 ? Theme.warning : Theme.text
            }
        }
        SettingRow {
            icon: "reload"
            label: "Charge cycles"
            hint: page.b.cycles > 0 ? "Full charges' worth of use so far." : "The battery does not count its cycles."
            Label { text: page.b.cycles > 0 ? String(page.b.cycles) : "—"; font.pixelSize: Theme.fsL; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
        }
        SettingRow {
            icon: "chip"
            label: [page.b.vendor, page.b.model].filter(x => x).join(" ") || "Battery"
            hint: page.b.technology || "Made by the manufacturer"
        }
        SettingRow {
            icon: "shield"
            label: "Limit charging to " + Battery.healthLimit + "%"
            hint: page.b.limit < 0 ? "This battery cannot be told to stop early."
                : page.b.limitWritable ? (page.limited ? "Stops at " + page.b.limit + "%. Best while it stays plugged in for weeks; turn it off before you travel."
                                                       : "Charges to 100%. Turn this on while it stays plugged in for weeks.")
                : !page.b.limitHelper ? "Read only: needs battery-charge-limit from modules/nixos/battery.nix."
                : "Read only: the boot service has not opened the threshold to the wheel group yet."
            // A Row, so the hidden one takes no room.
            Row {
                Toggle {
                    visible: page.b.limitWritable
                    checked: page.limited
                    onToggled: v => Battery.setLimit(v)
                }
                Label {
                    visible: !page.b.limitWritable
                    text: page.b.limit < 0 ? "Not supported" : page.limited ? "Stops at " + page.b.limit + "%" : "Off"
                    color: Theme.text2
                }
            }
        }
    }

    // ------------------------------------------------------------ power mode

    Section {
        title: "Power mode"
        hint: "How hard the processor and fans work."
        Component.onCompleted: page.mark("mode", this)
    }
    Notice {
        visible: !page.m.available
        text: "Power modes need power-profiles-daemon, which is not running here (services.power-profiles-daemon in NixOS)."
    }
    Card {
        visible: page.m.available
        divided: true
        Repeater {
            model: [
                { "id": "performance", "t": "Performance", "s": "Fastest. Uses more power and runs warmer." },
                { "id": "balanced", "t": "Balanced", "s": "Full speed when it is needed, quiet the rest of the time." },
                { "id": "power-saver", "t": "Power Saver", "s": "Slower and cooler, so the battery lasts longer." }
            ]
            ListRow {
                required property var modelData
                readonly property bool missing: modelData.id === "performance" && !page.m.hasPerformance
                title: modelData.t
                subtitle: missing ? "Not available on this hardware" : modelData.s
                selected: page.m.profile === modelData.id
                clickable: !missing && !selected
                dim: missing
                onClicked: Power.setProfile(modelData.id)
            }
        }
    }
    Notice {
        visible: page.m.available && page.m.degraded !== ""
        Layout.topMargin: 8
        icon: "info"
        text: "Performance is held back: " + (page.m.degraded === "hot" ? "the computer is too hot." : "it is on a lap.")
    }
    Repeater {
        model: page.m.available ? page.m.holds : []
        Notice {
            required property var modelData
            Layout.topMargin: 8
            icon: "info"
            text: (modelData.app || "An app") + " holds " + Power.profileLabel(modelData.profile) + (modelData.reason ? ": " + modelData.reason : ".")
        }
    }
    Text {
        visible: page.m.available && page.m.auto
        text: "This computer picks Performance when it is plugged in and Balanced on battery (power-profile-auto). A choice here lasts until the next plug or unplug."
        color: Theme.text2; font.family: Theme.ui; font.pixelSize: Theme.fsS
        wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
        Layout.fillWidth: true; Layout.topMargin: 8
    }

    // ------------------------------------------------------------ lid and idle

    Section {
        title: page.p.hasLid ? "Lid and idle" : "When idle"
        hint: page.p.hasLid ? "NixOS decides what the lid does (modules/nixos/power.nix); Folio decides when to lock and hibernate."
                            : "Folio decides when to lock and hibernate."
        Component.onCompleted: page.mark("lid", this)
    }
    Card {
        visible: page.p.hasLid
        divided: true
        SettingRow {
            icon: "laptop"; label: "Close the lid on battery"
            Label { text: Power.lidWords(page.p.lid); color: Theme.text2; width: Math.min(implicitWidth, 220) }
        }
        SettingRow {
            icon: "bolt"; label: "Close the lid when plugged in"
            hint: page.p.lidAC === "ignore" ? "It keeps working with the lid shut, for weeks unattended." : ""
            Label { text: Power.lidWords(page.p.lidAC); color: Theme.text2; width: Math.min(implicitWidth, 220) }
        }
        SettingRow {
            icon: "display"; label: "Close the lid with a display connected"
            Label { text: Power.lidWords(page.p.lidDocked); color: Theme.text2; width: Math.min(implicitWidth, 220) }
        }
    }
    Card {
        Layout.topMargin: page.p.hasLid ? 12 : 0
        divided: true
        SettingRow {
            icon: "lock"; label: "Lock"
            hint: Settings.get("screensaver.after") > 0 ? "The screensaver comes first, after " + page.minutes(Settings.get("screensaver.after")) + "." : ""
            Label {
                text: page.b.present ? page.minutes(Settings.get("idle.lockBattery")) + " on battery · " + page.minutes(Settings.get("idle.lockAC")) + " plugged in"
                                     : "After " + page.minutes(Settings.get("idle.lockAC"))
                color: Theme.text2; width: Math.min(implicitWidth, 260)
            }
        }
        SettingRow {
            icon: "display"; label: "Screens off"
            Label { text: Settings.get("idle.screensOff") > 0 ? page.minutes(Settings.get("idle.screensOff")) + " after locking" : "Never"; color: Theme.text2; width: Math.min(implicitWidth, 260) }
        }
        SettingRow {
            visible: page.b.present
            icon: "moon"; label: "Hibernate on battery"
            hint: "Plugged in, it never sleeps on its own."
            Label { text: Settings.get("idle.hibernateBattery") > 0 ? "After " + page.minutes(Settings.get("idle.hibernateBattery")) : "Never"; color: Theme.text2; width: Math.min(implicitWidth, 260) }
        }
        SettingRow {
            icon: "cup"; label: "Keep awake"
            hint: "Holds off the screensaver, the lock and hibernation until you turn it off."
            Toggle { checked: Awake.on; onToggled: v => { if (Power.fixture === "") Awake.set(v); } }
        }
        ListRow {
            title: "Change these in Lock & screensaver"
            Icon { name: "right"; size: 16; color: Theme.text2 }
            // Settings is open (this page is in it): go to the section in
            // place, as the navigation does. Shell.openSettings() would close
            // and rebuild the window under this handler.
            onClicked: { if (Shell.settingsOpen) Shell.settingsPage = "lock"; else Shell.openSettings("lock"); }
        }
    }

    // ------------------------------------------------------------ low battery

    Section {
        visible: page.b.present
        title: "Low battery"
        hint: "What warns you, and what happens at the end. UPower sets the levels."
        Component.onCompleted: page.mark("low", this)
    }
    Card {
        visible: page.b.present
        divided: true
        SettingRow {
            icon: "bell"; label: "Reminder"
            hint: page.m.available ? "A note above the dock, with a switch to Power Saver." : "A note above the dock."
            Label { text: "At " + page.p.lowAt + "%"; color: Theme.text2 }
        }
        SettingRow {
            icon: "battery"; label: "Warning"
            hint: "A note that stays until you plug in. The island flashes and the bar turns red at 10%."
            Label { text: "At " + page.p.criticalAt + "%"; color: Theme.text2 }
        }
        SettingRow {
            visible: Power.criticalWords(page.p.criticalAction) !== ""
            icon: page.p.criticalAction === "PowerOff" ? "power" : "moon"
            label: { const w = Power.criticalWords(page.p.criticalAction); return w.charAt(0).toUpperCase() + w.slice(1); }
            hint: page.p.criticalAction === "Hibernate" ? "The session is saved to the encrypted disk before the battery runs out." : "UPower's last resort before the battery runs out."
            Label { text: "At " + page.p.actionAt + "%"; color: Theme.text2 }
        }
    }
    Notice {
        visible: page.b.present && !Power.alertsActive
        Layout.topMargin: 8
        text: "The reminder and warning are off: the PowerAlerts module is not loaded."
    }
}
