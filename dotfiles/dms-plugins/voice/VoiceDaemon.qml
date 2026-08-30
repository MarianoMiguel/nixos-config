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

    PluginGlobalVar {
        id: agentState
        varName: "agentState"
        defaultValue: "offline"
    }

    PluginGlobalVar {
        id: agentRunning
        varName: "agentRunning"
        defaultValue: false
    }

    PluginGlobalVar {
        id: agentPending
        varName: "agentPending"
        defaultValue: null
    }

    PluginGlobalVar {
        id: agentTranscript
        varName: "agentTranscript"
        defaultValue: []
    }

    PluginGlobalVar {
        id: dictating
        varName: "dictating"
        defaultValue: "idle"
    }

    DankSocket {
        id: agent

        path: root.agentSocket
        connected: root.agentSocket !== ""

        onConnectionStateChanged: {
            if (!linkUp) {
                agentState.set("offline");
                agentRunning.set(false);
                agentPending.set(null);
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

        const previous = agentPending.value;
        agentState.set(message.state || "idle");
        agentRunning.set(message.running === true);
        agentPending.set(message.pending || null);
        agentTranscript.set(message.transcript || []);

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
            dictating.set(raw || "idle");
        }
        onLoadFailed: dictating.set("idle")
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
                agent: agentState.value,
                running: agentRunning.value,
                pending: agentPending.value,
                dictation: dictating.value
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
