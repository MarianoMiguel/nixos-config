// Watches the niri-modes daemon and mirrors its state into plugin globals.
//
// The daemon owns all mode state and enforcement; the shell is only a view
// and a remote control. The keybinds in dotfiles/niri/modes.kdl keep working
// with this plugin disabled, or with DMS not running at all.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    readonly property string modesSocket: runtimeDir ? runtimeDir + "/niri-modes.sock" : ""

    PluginGlobalVar {
        id: modesOutputs
        varName: "modesOutputs"
        defaultValue: ({})
    }

    PluginGlobalVar {
        id: modesConnected
        varName: "modesConnected"
        defaultValue: false
    }

    DankSocket {
        id: modes

        path: root.modesSocket
        connected: root.modesSocket !== ""

        onConnectionStateChanged: {
            modesConnected.set(linkUp);
            if (linkUp) {
                modes.send({
                    op: "watch"
                });
            } else {
                modesOutputs.set({});
            }
        }

        parser: SplitParser {
            onRead: line => root._handleLine(line)
        }
    }

    function _handleLine(line) {
        if (!line || !line.trim())
            return;
        let message;
        try {
            message = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (message.type !== "state")
            return;
        modesOutputs.set(message.outputs || {});
    }

    Component.onCompleted: console.info("WorkspaceModes: watching", root.modesSocket)
}
