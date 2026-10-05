import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.ControlCenter.Widgets

Column {
    id: root
    required property var sidebar
    spacing: 10
    readonly property var outputs: AudioService.typedSinks.filter(n => !n.isStream && !(SessionData.hiddenOutputDeviceNames || []).includes(n.name)).sort((a, b) => a === AudioService.sink ? -1 : b === AudioService.sink ? 1 : AudioService.displayName(a).localeCompare(AudioService.displayName(b)))
    readonly property var inputs: AudioService.typedSources.filter(n => !n.isStream && !(SessionData.hiddenInputDeviceNames || []).includes(n.name)).sort((a, b) => a === AudioService.source ? -1 : b === AudioService.source ? 1 : AudioService.displayName(a).localeCompare(AudioService.displayName(b)))
    readonly property var pods: SystemTray.items.values.find(item => item.id === "librepods") || null
    function deviceName(node) {
        const name = AudioService.displayName(node);
        if (AudioService.getDeviceAlias(node.name)) return name;
        return name.replace(/^.*\b(HDMI\s*\/\s*DisplayPort\s+\d+)\s*(?:Output)?$/i, "$1");
    }
    Component.onCompleted: sidebar.reportPanel("sound", true)

    StyledText {
        text: "OUTPUT"; color: Theme.surfaceVariantText
        font.family: SettingsData.monoFontFamily; font.pixelSize: 10; font.letterSpacing: 1
    }
    AudioSliderRow { width: parent.width }
    Repeater {
        model: root.outputs
        AudioDeviceButton {
            required property var modelData
            width: root.width
            label: root.deviceName(modelData)
            glyph: AudioService.sinkIcon(modelData)
            selected: modelData === AudioService.sink
            onClicked: AudioService.setSink(modelData)
        }
    }
    StyledText {
        visible: root.outputs.length === 0
        text: "No output device connected"; color: Theme.surfaceVariantText
        font.pixelSize: 12
    }
    StyledText {
        text: "MICROPHONE"; color: Theme.surfaceVariantText; topPadding: 10
        font.family: SettingsData.monoFontFamily; font.pixelSize: 10; font.letterSpacing: 1
    }
    InputAudioSliderRow { width: parent.width }
    Repeater {
        model: root.inputs
        AudioDeviceButton {
            required property var modelData
            width: root.width
            label: root.deviceName(modelData)
            glyph: "mic"
            selected: modelData === AudioService.source
            onClicked: AudioService.setSource(modelData)
        }
    }
    StyledText {
        visible: root.inputs.length === 0
        text: "No microphone connected"; color: Theme.surfaceVariantText
        font.pixelSize: 12
    }

    // Read LibrePods' exported menu rather than reverse-engineering its Bluetooth
    // protocol. Entries, checked state and availability remain owned by LibrePods.
    QsMenuOpener { id: podsMenu; menu: root.pods?.menu ?? null }
    readonly property var noiseControls: (podsMenu.children?.values || []).filter(entry => entry.buttonType === QsMenuButtonType.RadioButton)
    onNoiseControlsChanged: sidebar.reportPanel("librepodsMenu", noiseControls.length > 0)
    Column {
        width: parent.width; spacing: 8
        visible: root.pods !== null
        StyledText {
            text: "AIRPODS · LIBREPODS"; color: Theme.surfaceVariantText; topPadding: 10
            font.family: SettingsData.monoFontFamily; font.pixelSize: 10; font.letterSpacing: 1
        }
        StyledText {
            width: parent.width
            text: {
                const status = root.pods?.tooltipDescription || "";
                return !status || status.includes("?") ? "Battery status unavailable" : status;
            }
            textFormat: Text.PlainText
            color: Theme.surfaceVariantText; font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
        Repeater {
            model: root.noiseControls
            AudioDeviceButton {
                required property var modelData
                width: root.width
                label: modelData.text.replace(/&/g, "")
                glyph: "headphones"
                selected: modelData.checkState === Qt.Checked
                enabled: modelData.enabled
                onClicked: modelData.triggered()
            }
        }
        AudioDeviceButton {
            width: parent.width
            label: "Open LibrePods"; glyph: "open_in_new"
            onClicked: { root.sidebar.close(); root.pods?.activate(); }
        }
    }
    AudioDeviceButton {
        width: parent.width
        label: "More sound settings"; glyph: "tune"
        onClicked: { root.sidebar.close(); PopoutService.openSettingsWithTab("audio"); }
    }
}
