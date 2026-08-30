// The voice agent's floating panel: a level blurb with the running transcript
// underneath it.
//
// Run standalone by voiceagentd (`quickshell -p overlay.qml`) rather than as a
// DankMaterialShell plugin, so it appears whether or not DMS is running and
// survives a shell restart. It is a layer-shell surface, so it floats above the
// tiling layout without becoming a niri window that steals focus from the
// terminal we are about to type into.
//
// State is a JSON file the daemon rewrites; FileView watches it. A file rather
// than a socket because the overlay may start after, before, or several times
// during a session, and a file has no connection to miss.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string statePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/voiceagent/overlay.json"

    property string mode: "idle"
    property real level: 0
    property string partial: ""
    property string lastSent: ""
    property bool showing: false
    // "agent" or "dictate": the same panel serves both, and the caption is the
    // only thing that says where the words are about to go.
    property string target: "agent"

    // Resolved by the daemon from DankMaterialShell's active theme, so the
    // panel matches the rest of the desktop instead of inventing a palette.
    property var colors: ({})

    // Follows both the DMS corner radius and the Mod+Ctrl+B squared-off
    // toggle. Zero means the desktop is in square mode and this panel has no
    // business being the one rounded thing on screen.
    property int cornerRadius: 12

    function role(name, fallback) {
        const value = colors[name];
        return value !== undefined && value !== "" ? value : fallback;
    }

    readonly property color accent: {
        switch (mode) {
        case "listening":
            return role("primary", "#7dd3fc");
        case "transcribing":
            return role("tertiary", "#c084fc");
        case "sending":
        case "typing":
        case "sent":
            return role("secondary", "#b4e4f6");
        case "error":
            return role("error", "#f87171");
        default:
            return role("surfaceVariantText", "#94a3b8");
        }
    }

    readonly property color panelColor: role("surfaceContainer", "#11151c")
    readonly property color textColor: role("surfaceText", "#e2e8f0")
    readonly property color mutedColor: role("surfaceVariantText", "#94a3b8")

    readonly property string caption: {
        switch (mode) {
        case "listening":
            return root.target === "dictate" ? "Listening" : "Listening for a prompt";
        case "transcribing":
            return "Transcribing";
        case "typing":
            return "Typing";
        case "sending":
            return "Sending to the agent";
        case "sent":
            return "Sent";
        case "starting":
            return "Starting";
        case "error":
            return "Something went wrong";
        default:
            return "Idle";
        }
    }

    FileView {
        id: stateFile

        path: root.statePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const payload = JSON.parse(text());
                root.mode = payload.mode || "idle";
                root.level = payload.level || 0;
                root.partial = payload.partial || "";
                root.lastSent = payload.lastSent || "";
                root.showing = payload.showing === true;
                if (payload.target)
                    root.target = payload.target;
                if (payload.colors)
                    root.colors = payload.colors;
                if (payload.radius !== undefined)
                    root.cornerRadius = payload.radius;
            } catch (e) {
                // A half-written file is normal; the next change re-reads it.
            }
        }
    }

    PanelWindow {
        visible: root.showing

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "voiceagent"
        // Never take the keyboard: the whole point is that focus stays with,
        // or moves to, the Claude Code terminal.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            right: true
        }
        margins {
            top: 12
            right: 12
        }

        implicitWidth: 420
        implicitHeight: body.implicitHeight + 28
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            // The theme's container colour, held slightly translucent so the
            // panel reads as an overlay rather than a pasted-on rectangle.
            color: Qt.rgba(root.panelColor.r, root.panelColor.g, root.panelColor.b, 0.93)
            border.width: 1
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5)

            Column {
                id: body

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 9

                Row {
                    spacing: 11
                    width: parent.width

                    // The blurb: bars riding the input level, so silence looks
                    // different from speech at a glance.
                    Row {
                        spacing: 3
                        height: 30
                        anchors.verticalCenter: parent.verticalCenter

                        Repeater {
                            model: 16

                            Rectangle {
                                width: 3
                                radius: root.cornerRadius > 0 ? 1.5 : 0
                                color: root.accent
                                anchors.verticalCenter: parent.verticalCenter

                                // Centre bars react most, which reads as a
                                // voice envelope rather than a bar chart.
                                readonly property real weight: 1.0 - Math.abs(index - 7.5) / 9.0
                                readonly property real jitter: 0.7 + 0.3 * Math.sin(index * 2.3)

                                height: {
                                    if (root.mode === "idle")
                                        return 3;
                                    if (root.mode === "listening")
                                        return 3 + Math.min(1, root.level) * 27 * weight * jitter;
                                    return 3 + 11 * weight * sweep.value;
                                }

                                Behavior on height {
                                    NumberAnimation {
                                        duration: 70
                                        easing.type: Easing.OutQuad
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        text: root.caption
                        color: root.accent
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // What it heard, revealed a few characters at a time so the
                // transcript arriving is itself the feedback that it landed.
                // A misheard word is obvious here, before it goes anywhere.
                Text {
                    id: transcriptText

                    readonly property string fullText: root.partial !== "" ? root.partial : root.lastSent
                    property int revealed: 0

                    onFullTextChanged: {
                        // Extending the same sentence keeps typing from where
                        // it was; a different one restarts the reveal.
                        if (!fullText.startsWith(fullText.substring(0, revealed)))
                            revealed = 0;
                        reveal.restart();
                    }

                    Timer {
                        id: reveal
                        interval: 12
                        repeat: true
                        running: transcriptText.revealed < transcriptText.fullText.length
                        onTriggered: {
                            // Several characters per tick: one at a time reads
                            // as slow for a whole sentence.
                            transcriptText.revealed = Math.min(
                                transcriptText.fullText.length,
                                transcriptText.revealed + 3);
                        }
                    }

                    width: parent.width
                    visible: fullText !== ""
                    text: fullText.substring(0, revealed)
                    color: root.partial !== "" ? root.textColor : root.mutedColor
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: root.partial === "" && root.lastSent === ""
                    text: root.target === "dictate" ? "Speak, and it types into the focused window. Alt+A to stop." : "Speak one prompt. It goes to the agent, then the mic closes."
                    color: root.mutedColor
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // Drives the animation for states with no live level to show.
    QtObject {
        id: sweep

        property real value: 0.4
    }

    Timer {
        interval: 80
        running: root.showing && root.mode !== "listening" && root.mode !== "idle"
        repeat: true

        property real phase: 0

        onTriggered: {
            phase += 0.24;
            sweep.value = 0.3 + 0.7 * Math.abs(Math.sin(phase));
        }
    }
}
