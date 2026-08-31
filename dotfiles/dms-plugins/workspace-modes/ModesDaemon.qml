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

    // Last published state, kept locally so we can re-emit once pluginService
    // is injected (the daemon host assigns it after Component.onCompleted).
    property var _outputs: ({})
    property bool _connected: false

    function _publish(varName, value) {
        if (root.pluginService && root.pluginId)
            root.pluginService.setGlobalVar(root.pluginId, varName, value);
    }

    function _setOutputs(value) {
        root._outputs = value;
        root._publish("modesOutputs", value);
    }

    function _setConnected(value) {
        root._connected = value;
        root._publish("modesConnected", value);
    }

    onPluginServiceChanged: {
        // Push whatever we already know as soon as the shell wires us up.
        root._publish("modesConnected", root._connected);
        root._publish("modesOutputs", root._outputs);
    }

    DankSocket {
        id: modes

        path: root.modesSocket
        connected: root.modesSocket !== ""

        onConnectionStateChanged: {
            root._setConnected(linkUp);
            if (linkUp) {
                modes.send({
                    op: "watch"
                });
            } else {
                root._setOutputs({});
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
        root._setOutputs(message.outputs || {});
    }

    Component.onCompleted: console.info("WorkspaceModes: watching", root.modesSocket)
}
