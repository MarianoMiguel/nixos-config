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

    // Dictation wins the pill when it is live: it is the shorter, more frequent
    // interaction, and the user is mid-sentence with text about to appear.
    readonly property bool isDictating: dictating.value === "recording" || dictating.value === "transcribing"
    readonly property bool needsAnswer: agentPending.value !== null && agentPending.value !== undefined

    readonly property string iconName: {
        if (isDictating)
            return dictating.value === "transcribing" ? "hourglass_top" : "mic";
        if (needsAnswer)
            return "help";
        if (!agentRunning.value)
            return "mic_off";
        switch (agentState.value) {
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
        if (isDictating && dictating.value === "recording")
            return Theme.error;
        if (agentRunning.value)
            return Theme.primary;
        return Theme.surfaceText;
    }

    readonly property string label: {
        if (isDictating)
            return dictating.value === "recording" ? "Dictating" : "Transcribing";
        if (needsAnswer)
            return "Approve?";
        if (!agentRunning.value)
            return "";
        return agentState.value.charAt(0).toUpperCase() + agentState.value.slice(1);
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
            detailsText: root.agentRunning.value ? "Alt+S ends the session" : "Alt+S starts talking, Alt+A dictates"
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
                            text: root.agentPending.value ? (root.agentPending.value.title || "") : ""
                            font.pixelSize: Theme.fontSizeMedium
                            font.bold: true
                            wrapMode: Text.WordWrap
                        }

                        StyledText {
                            width: parent.width
                            text: root.agentPending.value ? (root.agentPending.value.detail || "") : ""
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
                        iconName: root.agentRunning.value ? "stop" : "play_arrow"
                        text: root.agentRunning.value ? "End session" : "Start talking"
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
                    model: root.agentTranscript.value

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
