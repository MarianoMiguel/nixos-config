import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// Sound: where sound plays and where it comes from, how loud each is, the
// card profile where there is a choice (Bluetooth high fidelity or headset,
// HDMI), the apps playing now, and sound effects. Everything reads and
// writes through Audio, which also serves the fixtures (`sound fixture …`).
SettingsPage {
    id: page
    title: "Sound"
    description: "Where sound plays and where it comes from, how loud each is, and the apps playing now."

    Component.onCompleted: { Audio.watching = true; Qt.callLater(page.revealAsked); }
    Component.onDestruction: Audio.watching = false
    function revealAsked() { if (Audio.reveal) { page.scrollTo(Audio.reveal); Audio.reveal = ""; } }
    Connections { target: Audio; function onRevealChanged() { page.revealAsked(); } }

    readonly property var out: Audio.dev(Audio.defaultOutput)
    readonly property var inp: Audio.dev(Audio.defaultInput)
    function balanceHint(b) {
        if (Math.abs(b) < 0.01) return "Even on both sides";
        return (b < 0 ? "Toward the left, " : "Toward the right, ") + Math.round(Math.abs(b) * 100) + "%";
    }

    Notice {
        visible: !Audio.available
        Layout.topMargin: 18
        icon: "speaker"
        text: "The sound service (PipeWire) is not answering. Devices and volumes come back here when it runs again."
    }

    // ---------------------------------------------------------------- output
    Section {
        visible: Audio.available
        title: "Output"; hint: "Where sound plays. The volume keys follow the device chosen here."
        Component.onCompleted: page.mark("output", this)
    }
    Card {
        visible: Audio.available && Audio.outputKeys.length + Audio.offCards.length > 0
        Repeater {
            model: ScriptModel { values: Audio.outputKeys }
            SoundDeviceRow { required property var modelData; required property int index; key: modelData; rule: index > 0 }
        }
        // Cards switched off: one press turns on their best profile.
        Repeater {
            model: ScriptModel { values: Audio.offCards }
            Item {
                id: off
                required property var modelData
                required property int index
                readonly property var c: Audio.card(modelData)
                Layout.fillWidth: true
                implicitHeight: offRow.implicitHeight
                ListRow {
                    id: offRow
                    width: parent.width
                    icon: !off.c ? "speaker" : off.c.api === "bluez5" ? "bluetooth" : off.c.bus === "usb" ? "usb" : /hdmi|radeon|nvidia|displayport/i.test(off.c.title) ? "display" : "speaker"
                    title: off.c ? off.c.title : ""
                    subtitle: "Turned off"
                    dim: true
                    clickable: false
                    Button { text: "Turn on"; onClicked: Audio.turnOn(off.modelData) }
                }
                Rectangle { visible: off.index > 0 || Audio.outputKeys.length > 0; x: 14; width: parent.width - 28; height: 1; color: Theme.rule }
            }
        }
    }
    Notice {
        visible: Audio.available && Audio.outputKeys.length + Audio.offCards.length === 0
        icon: "speaker"
        text: "No speakers or headphones found. Plug some in, or connect Bluetooth headphones."
        action: "Bluetooth"
        onActed: Shell.openSettings("bluetooth")
    }
    Card {
        visible: Audio.available && page.out.ok
        Layout.topMargin: 10
        divided: true
        SoundLevelRow {
            icon: "speaker"; label: "Volume"
            hint: page.out.muted ? "Muted" : page.out.title
            value: page.out.volume; muted: page.out.muted; to: Audio.maxVolume
            onMoved: v => Audio.setDeviceVolume(page.out.key, v)
            onMuteToggled: Audio.setDeviceMuted(page.out.key, !page.out.muted)
        }
        SoundRow {
            visible: page.out.hasBalance
            icon: "headphones"; label: "Balance"; hint: page.balanceHint(page.out.balance)
            Cap { text: "L"; Layout.preferredWidth: 41; horizontalAlignment: Text.AlignRight }
            SoundBalance { Layout.fillWidth: true; Layout.minimumWidth: 80; value: page.out.balance; onMoved: b => Audio.setBalance(page.out.key, b) }
            Cap { text: "R"; Layout.preferredWidth: 42 }
        }
        SoundProfiles { cardKey: page.out.card; panel: "output" }
        SettingRow {
            icon: "bolt"; label: "Allow volume above 100%"
            hint: "Up to 150% for quiet speakers and recordings. Loud sound may distort."
            Toggle { checked: Audio.overAmplify; onToggled: v => Audio.setOverAmplify(v) }
        }
    }

    // ---------------------------------------------------------------- input
    Section {
        visible: Audio.available
        title: "Input"; hint: "The microphone apps use unless they choose their own."
        Component.onCompleted: page.mark("input", this)
    }
    Card {
        visible: Audio.available && Audio.inputKeys.length > 0
        Repeater {
            model: ScriptModel { values: Audio.inputKeys }
            SoundDeviceRow { required property var modelData; required property int index; key: modelData; rule: index > 0 }
        }
    }
    Notice {
        visible: Audio.available && Audio.inputKeys.length === 0
        icon: "mic"
        text: "No microphones found. Plug one in, or use a headset's."
    }
    Card {
        visible: Audio.available && page.inp.ok
        Layout.topMargin: 10
        divided: true
        SoundLevelRow {
            icon: "mic"; label: "Input volume"
            hint: page.inp.muted ? "Muted" : page.inp.title
            value: page.inp.volume; muted: page.inp.muted
            onMoved: v => Audio.setDeviceVolume(page.inp.key, v)
            onMuteToggled: Audio.setDeviceMuted(page.inp.key, !page.inp.muted)
        }
        SoundRow {
            icon: "sparkle"; label: "Input level"
            hint: page.inp.muted ? "Muted" : "Speak to see it move"
            Item { Layout.preferredWidth: 41 }
            SoundMeter { Layout.fillWidth: true; Layout.leftMargin: 8; Layout.rightMargin: 8; level: Audio.inputLevel; dim: page.inp.muted }
            Item { Layout.preferredWidth: 42 }
        }
        SoundProfiles { allowed: page.inp.card !== page.out.card; cardKey: page.inp.card; panel: "input" }
    }

    // ---------------------------------------------------------------- apps
    Section {
        visible: Audio.available
        title: "Apps"; hint: "Each app playing sound: its own volume, and where it plays."
        Component.onCompleted: page.mark("apps", this)
    }
    Card {
        visible: Audio.available && Audio.streamKeys.length > 0
        Repeater {
            model: ScriptModel { values: Audio.streamKeys }
            SoundAppRow { required property var modelData; required property int index; key: modelData; rule: index > 0 }
        }
    }
    Notice {
        visible: Audio.available && Audio.streamKeys.length === 0
        icon: "music"
        text: "No apps are playing sound right now."
    }

    // ---------------------------------------------------------------- sound effects
    Section {
        title: "Sound effects"
        hint: "Short, quiet sounds for what the desktop does; press one to hear it. Notification sounds follow each app's switch in Notifications and keep quiet in Do not disturb."
        Component.onCompleted: page.mark("sounds", this)
    }
    Card {
        divided: true
        SettingRow {
            icon: "sparkle"; label: "Interface sounds"
            hint: "Volume keys, screenshots, the Trash, devices, power and the lock screen"
            Toggle { checked: Audio.sounds; onToggled: v => Audio.setSounds(v) }
        }
        SoundEffectsLevel {}
        SoundEffects {}
    }
}
