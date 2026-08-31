// Bar pill for voice input, plus the popout that answers the agent's
// "should I?" without needing the keyboard.

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "voice"

    // Mirror the daemon's plugin-global state. getGlobalVar is read on demand
    // and refreshed whenever the daemon publishes via globalVarChanged.
    property string agentState: "offline"
    property bool agentRunning: false
    property var agentPending: null
    property var agentTranscript: []
    property string dictating: "idle"

    function _refreshGlobals() {
        if (!root.pluginService || !root.pluginId) {
            root.agentState = "offline";
            root.agentRunning = false;
            root.agentPending = null;
            root.agentTranscript = [];
            root.dictating = "idle";
            return;
        }
        root.agentState = root.pluginService.getGlobalVar(root.pluginId, "agentState", "offline");
        root.agentRunning = root.pluginService.getGlobalVar(root.pluginId, "agentRunning", false);
        root.agentPending = root.pluginService.getGlobalVar(root.pluginId, "agentPending", null);
        root.agentTranscript = root.pluginService.getGlobalVar(root.pluginId, "agentTranscript", []);
        root.dictating = root.pluginService.getGlobalVar(root.pluginId, "dictating", "idle");
    }

    onPluginServiceChanged: root._refreshGlobals()
    Component.onCompleted: root._refreshGlobals()

    Connections {
        target: root.pluginService
        function onGlobalVarChanged(changedPluginId, varName) {
            if (changedPluginId === root.pluginId)
                root._refreshGlobals();
        }
    }

    // Dictation wins the pill when it is live: it is the shorter, more frequent
    // interaction, and the user is mid-sentence with text about to appear.
    readonly property bool isDictating: root.dictating === "recording" || root.dictating === "transcribing"
    readonly property bool needsAnswer: root.agentPending !== null && root.agentPending !== undefined

    readonly property string iconName: {
        if (isDictating)
            return root.dictating === "transcribing" ? "hourglass_top" : "mic";
        if (needsAnswer)
            return "help";
        if (!root.agentRunning)
            return "mic_off";
        switch (root.agentState) {
        case "listening":
            return "graphic_eq";
        case "thinking":
            return "neurology";
        case "speaking":
            return "volume_up";
        case "transcribing":
            return "hourglass_top";
        default:
            return "assistant";
        }
    }

    readonly property color iconColor: {
        if (needsAnswer)
            return Theme.warning;
        if (isDictating && root.dictating === "recording")
            return Theme.error;
        if (root.agentRunning)
            return Theme.primary;
        return Theme.surfaceText;
    }

    readonly property string label: {
        if (isDictating)
            return root.dictating === "recording" ? "Dictating" : "Transcribing";
        if (needsAnswer)
            return "Approve?";
        if (!root.agentRunning)
            return "";
        return root.agentState.charAt(0).toUpperCase() + root.agentState.slice(1);
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.iconName
                size: Theme.iconSize
                color: root.iconColor
                anchors.verticalCenter: parent.verticalCenter

                SequentialAnimation on opacity {
                    running: root.isDictating || root.needsAnswer
                    loops: Animation.Infinite
                    NumberAnimation {
                        to: 0.35
                        duration: 700
                    }
                    NumberAnimation {
                        to: 1.0
                        duration: 700
                    }
                    onRunningChanged: {
                        if (!running)
                            root.opacity = 1.0;
                    }
                }
            }

            StyledText {
                text: root.label
                visible: text !== ""
                color: root.iconColor
                font.pixelSize: Theme.fontSizeSmall
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: root.iconName
            size: Theme.iconSize
            color: root.iconColor
        }
    }

    popoutWidth: 460
    popoutHeight: 520

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: "Voice"
            detailsText: root.agentRunning ? "Alt+S ends the session" : "Alt+S starts talking, Alt+A dictates"
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // The approval prompt sits at the top because the agent is
                // blocked until it is answered.
                StyledRect {
                    width: parent.width
                    visible: root.needsAnswer
                    height: visible ? approvalColumn.implicitHeight + Theme.spacingM * 2 : 0
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHighest
                    border.width: 1
                    border.color: Theme.warning

                    Column {
                        id: approvalColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        StyledText {
                            width: parent.width
                            text: root.agentPending ? (root.agentPending.title || "") : ""
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                            wrapMode: Text.WordWrap
                        }

                        StyledText {
                            width: parent.width
                            text: root.agentPending ? (root.agentPending.detail || "") : ""
                            visible: text !== ""
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WrapAnywhere
                            maximumLineCount: 6
                            elide: Text.ElideRight
                        }

                        Row {
                            spacing: Theme.spacingS

                            DankButton {
                                iconName: "check"
                                text: "Approve"
                                backgroundColor: Theme.primary
                                textColor: Theme.onPrimary
                                onClicked: Quickshell.execDetached(["voiceagent", "approve"])
                            }

                            DankButton {
                                iconName: "close"
                                text: "Deny"
                                onClicked: Quickshell.execDetached(["voiceagent", "deny"])
                            }
                        }
                    }
                }

                Row {
                    spacing: Theme.spacingS

                    DankButton {
                        iconName: root.agentRunning ? "stop" : "play_arrow"
                        text: root.agentRunning ? "End session" : "Start talking"
                        onClicked: Quickshell.execDetached(["voiceagent", "toggle"])
                    }

                    DankButton {
                        iconName: "keyboard_voice"
                        text: root.isDictating ? "Stop dictation" : "Dictate"
                        onClicked: Quickshell.execDetached(["voxtype", "record", "toggle"])
                    }
                }

                DankListView {
                    id: transcriptView

                    width: parent.width
                    height: popout.height - popout.headerHeight - popout.detailsHeight - Theme.spacingXL * 4
                    clip: true
                    model: root.agentTranscript

                    // Oldest first, so the newest line is at the bottom and the
                    // view has to follow it as the conversation grows.
                    onCountChanged: Qt.callLater(positionViewAtEnd)

                    delegate: Column {
                        width: ListView.view.width
                        spacing: 2
                        bottomPadding: Theme.spacingS

                        StyledText {
                            text: (modelData.role === "user" ? "You" : modelData.role === "assistant" ? "Claude" : "System") + "  " + (modelData.at || "")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            width: parent.width
                            text: modelData.text || ""
                            wrapMode: Text.WordWrap
                            font.pixelSize: Theme.fontSizeSmall
                            color: modelData.role === "system" ? Theme.surfaceVariantText : Theme.surfaceText
                        }
                    }
                }
            }
        }
    }
}
