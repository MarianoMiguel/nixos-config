// Bridges the two voice services into the shell.
//
// The agent is reached over its own unix socket rather than the other way
// round, so the shell is a view and a remote control, never the control path:
// tapping Alt three times works with this plugin disabled, or with DMS not
// running at all.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    readonly property string agentSocket: runtimeDir ? runtimeDir + "/voiceagent.sock" : ""
    readonly property string dictationState: runtimeDir ? runtimeDir + "/voxtype/state" : ""

    // Local shadow of the plugin-global state. Kept here so we can read our own
    // values back in the IpcHandler and re-publish everything once pluginService
    // is injected (the daemon host assigns it after Component.onCompleted).
    property string agentState: "offline"
    property bool agentRunning: false
    property var agentPending: null
    property var agentTranscript: []
    property string dictating: "idle"

    function _publish(varName, value) {
        if (root.pluginService && root.pluginId)
            root.pluginService.setGlobalVar(root.pluginId, varName, value);
    }

    function _setAgentState(value) {
        root.agentState = value;
        root._publish("agentState", value);
    }
    function _setAgentRunning(value) {
        root.agentRunning = value;
        root._publish("agentRunning", value);
    }
    function _setAgentPending(value) {
        root.agentPending = value;
        root._publish("agentPending", value);
    }
    function _setAgentTranscript(value) {
        root.agentTranscript = value;
        root._publish("agentTranscript", value);
    }
    function _setDictating(value) {
        root.dictating = value;
        root._publish("dictating", value);
    }

    onPluginServiceChanged: {
        // Push whatever we already know as soon as the shell wires us up.
        root._publish("agentState", root.agentState);
        root._publish("agentRunning", root.agentRunning);
        root._publish("agentPending", root.agentPending);
        root._publish("agentTranscript", root.agentTranscript);
        root._publish("dictating", root.dictating);
    }

    DankSocket {
        id: agent

        path: root.agentSocket
        connected: root.agentSocket !== ""

        onConnectionStateChanged: {
            if (!linkUp) {
                root._setAgentState("offline");
                root._setAgentRunning(false);
                root._setAgentPending(null);
            }
        }

        parser: SplitParser {
            onRead: line => root._handleAgentLine(line)
        }
    }

    function _handleAgentLine(line) {
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

        const previous = root.agentPending;
        root._setAgentState(message.state || "idle");
        root._setAgentRunning(message.running === true);
        root._setAgentPending(message.pending || null);
        root._setAgentTranscript(message.transcript || []);

        // A tool call waiting on an answer is the one thing worth interrupting
        // the user for: nothing happens until it is answered.
        if (message.pending && !previous)
            ToastService.showWarning("Voice agent", message.pending.title || "Waiting for approval");
    }

    // voxtype writes idle/recording/transcribing here. Watching the file keeps
    // the pill honest whether dictation was started by Alt+A, from this
    // popout, or from a terminal.
    FileView {
        id: dictationFile

        path: root.dictationState
        watchChanges: root.dictationState !== ""
        onFileChanged: reload()
        onLoaded: {
            const raw = (text() || "").trim();
            root._setDictating(raw || "idle");
        }
        onLoadFailed: root._setDictating("idle")
    }

    IpcHandler {
        target: "voice"

        function toggle(): string {
            return root._send("toggle");
        }

        function start(): string {
            return root._send("start");
        }

        function stop(): string {
            return root._send("stop");
        }

        function approve(): string {
            return root._send("approve");
        }

        function deny(): string {
            return root._send("deny");
        }

        function interrupt(): string {
            return root._send("interrupt");
        }

        function status(): string {
            return JSON.stringify({
                agent: root.agentState,
                running: root.agentRunning,
                pending: root.agentPending,
                dictation: root.dictating
            });
        }

        function dictate(): string {
            Quickshell.execDetached(["voxtype", "record", "toggle"]);
            return "toggled dictation";
        }
    }

    function _send(command) {
        if (!agent.linkUp)
            return "voiceagent is not running";
        agent.send({
            cmd: command
        });
        return "sent " + command;
    }

    Component.onCompleted: console.info("Voice: watching", root.agentSocket)
}
