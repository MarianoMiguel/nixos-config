import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// One screen's bar. The left side stops short of the island's 340 px: the
// app name elides at 180 px and the window title fades out before the edge.
PanelWindow {
    id: win

    Entrance { target: win.contentItem; part: "bar"; fromY: -34 }

    property var fx: null
    property int fakeActive: -1          // a fixture's workspace picked by click
    onFxChanged: fakeActive = -1
    readonly property string output: screen ? screen.name : ""
    readonly property real islandRoom: 340

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "folio:bar"
    anchors { top: true; left: true; right: true }
    implicitHeight: 34
    exclusiveZone: 34
    color: "transparent"
    BackgroundEffect.blurRegion: Region { item: paper }

    // Live data, or the fixture's.
    readonly property var workspaces: {
        if (fx) return Array.from({ length: fx.workspaces }, (_, i) => ({ "id": -1, "idx": i + 1, "is_active": i === (fakeActive >= 0 ? fakeActive : fx.active) }));
        const list = Niri.workspacesOn(output);
        return list.length ? list : [{ "id": -1, "idx": 1, "is_active": true }];
    }
    readonly property var window: {
        if (fx) return null;
        const ws = Niri.workspacesOn(output).find(w => w.is_active);
        return (ws && Niri.windows[ws.active_window_id]) || Niri.focusedWindow;
    }
    readonly property string appName: {
        if (fx) return fx.app;
        if (!window) return "Desktop";
        const entry = window.app_id ? DesktopEntries.heuristicLookup(window.app_id) : null;
        return (entry && entry.name) || window.app_id || "Window";
    }
    readonly property string windowTitle: fx ? fx.title : window ? (window.title || "") : ""

    Rectangle {
        id: paper
        anchors.fill: parent
        color: Theme.sheet
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.rule }
    }

    // Left: mark, workspaces, app, title. Never wider than its half.
    RowLayout {
        x: 8
        width: Math.max(0, (win.width - 16 - win.islandRoom) / 2)
        height: parent.height
        spacing: 4

        // The monogram: opens the launcher.
        Rectangle {
            id: mark
            Layout.preferredWidth: 24; Layout.preferredHeight: 24
            radius: Theme.rXs
            color: Theme.ink
            scale: markArea.pressed ? 0.95 : 1
            Behavior on scale { SpringPress {} }
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 1
                text: "F"
                color: Theme.inkText
                font.family: Theme.hero
                font.pixelSize: 19
            }
            MouseArea {
                id: markArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Shell.openLauncher("")
            }
        }

        Workspaces {
            Layout.fillHeight: true
            model: win.workspaces
            onPicked: ws => {
                if (win.fx) win.fakeActive = ws.idx - 1;
                else if (ws.id >= 0) Niri.focusWorkspace(ws);
            }
        }

        Label {
            Layout.maximumWidth: 180 + 8
            Layout.minimumWidth: 0
            leftPadding: 4; rightPadding: 4
            text: win.appName
            font.weight: Font.DemiBold
        }

        // The title fades out at its end instead of eliding.
        Item {
            id: titleBox
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.fillHeight: true
            clip: true
            readonly property bool over: titleText.implicitWidth > width
            Item {
                id: titleStrip
                anchors.fill: parent
                layer.enabled: titleBox.over
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: titleFade
                    maskThresholdMin: 0.0
                    maskSpreadAtMin: 1.0
                }
                Label {
                    id: titleText
                    anchors.verticalCenter: parent.verticalCenter
                    width: implicitWidth
                    elide: Text.ElideNone
                    text: win.windowTitle
                    color: Theme.text2
                }
            }
            Item {
                id: titleFade
                anchors.fill: parent
                visible: false
                layer.enabled: true
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "white" }
                        GradientStop { position: Math.max(0, 1 - 32 / Math.max(1, titleBox.width)); color: "white" }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
            }
        }
    }

    // Right: privacy, date, tray, status.
    RowLayout {
        anchors.right: parent.right
        anchors.rightMargin: 8
        height: parent.height
        width: Math.min(implicitWidth, Math.max(0, (win.width - 16 - win.islandRoom) / 2))
        spacing: 4

        PrivacyPill {
            mic: win.fx ? win.fx.mic : Privacy.mic
            camera: win.fx ? win.fx.camera : Privacy.camera
            screen: win.fx ? win.fx.screen : Privacy.screen
        }

        Label {
            Layout.minimumWidth: 0
            leftPadding: 8; rightPadding: 8
            text: clock.date.toLocaleDateString(Qt.locale("en_GB"), "ddd d MMM")
            color: Theme.text2
            SystemClock { id: clock; precision: SystemClock.Minutes }
        }

        Tray {
            Layout.fillHeight: true
            bar: win
            fake: win.fx ? win.fx.tray : []
        }

        StatusPill { fx: win.fx }
    }
}
