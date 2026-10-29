import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// The authentication dialog on the focused screen: a halftone scrim (never
// flat black), and a strong sheet that prints in and settles from a little
// below; it lifts off when done. Typing goes to the cross grid.
PanelWindow {
    id: win
    required property var owner

    // The focused screen when the request arrives; it stays there.
    property var where: null
    screen: where || Shell.screenFor(Quickshell.screens)
    property bool shown: false
    visible: shown
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "folio:polkit"
    WlrLayershell.keyboardFocus: owner.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    BackgroundEffect.blurRegion: Region { item: dialog; radius: 22 + frost.extra }
    BlurNudge { id: frost; key: win.open }

    readonly property bool open: owner.open
    onOpenChanged: {
        if (open) {
            exitDelay.stop();
            if (!shown) where = Shell.screenFor(Quickshell.screens);
            shown = true;
            scrim.opacity = 0;
            scrimIn.restart();
            settle.restart();
            ink.printIn(320);
            focusScope.forceActiveFocus();
        } else if (shown) {
            // After a success the cells flood first.
            exitDelay.interval = owner.phase === "done" ? Math.max(1, 320 * Theme.motion) : 1;
            exitDelay.restart();
        }
    }
    Timer { id: exitDelay; onTriggered: { scrimOut.restart(); ink.lift(260); } }

    Halftone {
        id: scrim
        anchors.fill: parent
        ink: Theme.rgba(Theme.shade, 0.55)
        back: Theme.rgba(Theme.shade, 0.12)
        dotRadius: 1.1
        opacity: 0
    }
    NumberAnimation { id: scrimIn; target: scrim; property: "opacity"; to: 1; duration: 220 }
    NumberAnimation {
        id: scrimOut; target: scrim; property: "opacity"; to: 0; duration: 180
        onFinished: if (!win.open) win.shown = false
    }
    MouseArea { anchors.fill: parent; onClicked: win.owner.cancel() }

    FocusScope {
        id: focusScope
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => { event.accepted = true; win.owner.key(event); }
    }

    Item {
        id: dialog
        anchors.centerIn: parent
        anchors.verticalCenterOffset: lift
        width: 440
        height: body.implicitHeight + 44
        property real lift: 0
        MouseArea { anchors.fill: parent }

        SequentialAnimation {
            id: settle
            ParallelAnimation {
                NumberAnimation { target: dialog; property: "lift"; from: 10; to: 0; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1] }
                NumberAnimation { target: dialog; property: "scale"; from: 0.94; to: 1; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1] }
            }
        }

        Develop {
            id: ink
            anchors.fill: parent
            anchors.margins: -40               // room for the sheet's shadow
            progress: 0
            grain: 1.4

            Sheet {
                x: 40; y: 40
                width: dialog.width; height: dialog.height
                radius: 22
                color: Theme.sheetStrong

                ColumnLayout {
                    id: body
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
                    spacing: 14

                    Cap {
                        Layout.fillWidth: true; Layout.minimumWidth: 0
                        text: win.owner.actionId || "Authentication"
                    }
                    Label {
                        Layout.fillWidth: true; Layout.minimumWidth: 0
                        Layout.topMargin: -6
                        text: "Authentication required"
                        font.pixelSize: Theme.fsL + 1
                        font.weight: Font.DemiBold
                    }
                    Label {
                        Layout.fillWidth: true; Layout.minimumWidth: 0
                        visible: text !== ""
                        text: win.owner.actionMessage
                        color: Theme.text2
                        wrapMode: Text.Wrap
                        maximumLineCount: 4
                        lineHeight: 1.1
                    }
                    RowLayout {
                        spacing: 8
                        Layout.fillWidth: true
                        visible: win.owner.identity !== ""
                        Icon { name: "user"; size: 16; color: Theme.ink }
                        Label {
                            Layout.fillWidth: true; Layout.minimumWidth: 0
                            text: win.owner.identity
                            font.weight: Font.Medium
                        }
                    }

                    // The cross grid and its hints, as on the lock page.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 22
                        CrossGrid {
                            id: grid
                            cell: 30
                            count: win.owner.shown
                            text: win.owner.buffer
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.minimumWidth: 0
                            spacing: 10
                            RowLayout {
                                spacing: 10
                                Icon { name: "keyboard"; size: 20; color: Theme.ink }
                                Label { Layout.fillWidth: true; Layout.minimumWidth: 0; text: "Type your password"; color: Theme.text2 }
                            }
                            RowLayout {
                                visible: win.owner.fingerprint
                                spacing: 10
                                Icon {
                                    name: "fingerprint"; size: 20; color: Theme.ink
                                    SequentialAnimation on opacity {
                                        running: win.owner.fingerprint && win.visible; loops: Animation.Infinite
                                        NumberAnimation { to: 0.35; duration: 1300; easing.type: Easing.InOutCubic }
                                        NumberAnimation { to: 1; duration: 1300; easing.type: Easing.InOutCubic }
                                    }
                                }
                                Label { Layout.fillWidth: true; Layout.minimumWidth: 0; text: "or touch the sensor"; color: Theme.text2 }
                            }
                            Label {
                                Layout.fillWidth: true; Layout.minimumWidth: 0
                                Layout.minimumHeight: 20
                                text: win.owner.phase === "checking" ? "Checking…" : win.owner.note
                                color: win.owner.messageError || (!win.owner.message && win.owner.note) ? Theme.error : Theme.text3
                                font.weight: Font.Medium
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                            }
                            Cap { visible: win.owner.harness; text: "Try “folio”" }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 8
                        Item { Layout.fillWidth: true }
                        PolkitButton { text: "Cancel"; onClicked: win.owner.cancel() }
                        PolkitButton { text: "Authenticate"; ink: true; onClicked: win.owner.submit() }
                    }
                }
            }
        }
    }

    Connections {
        target: win.owner
        function onRefused() { grid.shake(); }
        function onAccepted() { grid.flood(); }
        function onOpenChanged() { if (win.owner.open) grid.reset(); }
    }
}
