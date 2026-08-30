// The services are configured declaratively in modules/nixos/voice.nix and in
// ~/.config/voiceagent/config.toml, so there is nothing here that would not
// immediately be overwritten. This panel explains where the knobs actually live.

import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root

    pluginId: "voice"

    Column {
        width: parent.width
        spacing: Theme.spacingM

        StyledText {
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeMedium
            font.bold: true
            text: "Gestures"
        }

        StyledText {
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            text: "Alt+A dictates into the focused window. Alt+S starts or ends a spoken session with Claude. Alt+D and Alt+U stay with keyd as PageDown and PageUp, which is why dictation is not on Alt+D."
        }

        StyledText {
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeMedium
            font.bold: true
            text: "Where the settings are"
        }

        StyledText {
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            text: "Keybinds: dotfiles/niri/voice.kdl\nAgent voice, microphone, and approval timeout: ~/.config/voiceagent/config.toml\nDictation: modules/nixos/home.nix (programs.voxtype)\nSpeech recognition model: modules/nixos/voice.nix"
        }

        StyledText {
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            text: "Everything runs locally. Speech never leaves this machine; only what Claude Code would already send does."
        }
    }
}
