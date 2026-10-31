import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// One screen's island: a deep-ink pill over the middle of the bar. Its size
// and corners move on a spring; faces cross-fade inside it; the album art is
// one element that grows from the music face into the player and back.
PanelWindow {
    id: win

    Entrance { target: win.contentItem; part: "island"; fromY: -12; fromScale: 0.7 }

    property var hub
    readonly property string output: screen ? screen.name : ""
    readonly property string face: hub ? hub.faceFor(output) : "idle"
    readonly property var info: hub ? hub.payload : ({})
    // Each transient face keeps its last payload, so it fades out unchanged.
    property var held: ({ "level": {}, "note": {}, "battery": {}, "layout": {} })
    function keep() {
        if (!(face in held) || !info) return;
        const h = Object.assign({}, held);
        h[face] = info;
        held = h;
    }
    onFaceChanged: { keep(); if (face === "player") keys.forceActiveFocus(); }
    onInfoChanged: keep()

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "folio:island"
    WlrLayershell.keyboardFocus: face === "player" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    implicitWidth: 460
    implicitHeight: 216
    color: "transparent"
    mask: Region { item: pill }

    // Each face's size; the layout face fits its name.
    readonly property var sizes: ({
        "idle": [96, 26], "music": [230, 30], "player": [380, 168], "focus": [210, 30], "recording": [260, 30],
        "note": [300, 34], "level": [250, 30], "battery": [held.battery.kind === "low" ? 300 : 200, 30],
        "layout": [Math.min(320, Math.max(160, 2 * Math.ceil((layoutName.implicitWidth + 61) / 2))), 30]
    })
    readonly property var size: sizes[face] || sizes.idle

    // Theme.island mixes from strings and comes out transparent (asked to be
    // fixed in Theme); until then, the same mix from real colors.
    readonly property color deep: Theme.island.a > 0 ? Theme.island
        : Theme.mix(Qt.color("#0b1424"), Qt.color((Theme.inks[Theme.inkName] || Theme.inks.azure)[0]), 0.46)
    // The island's alert reds: the error hue, lit for deep ink.
    readonly property color alert: Qt.hsla(Theme.error.hslHue, 0.8, 0.69, 1)
    readonly property color warm: Qt.hsla(Theme.error.hslHue, 0.8, 0.78, 1)

    // Text styles from the study: .t figures and .s secondary lines.
    component T: Label {
        color: Theme.islandText
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
    }
    component S: Label {
        color: Theme.islandText
        opacity: 0.7
        font.pixelSize: Theme.fsS
        Layout.fillWidth: true
        Layout.minimumWidth: 0
    }

    // Esc closes the player; it has the keyboard while open.
    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: win.hub.closePlayer()
    }

    RectangularShadow {
        anchors.fill: pill
        radius: pill.radius
        blur: 24
        offset: Qt.vector2d(0, 6)
        spread: -1
        color: Theme.rgba(Theme.shade, 0.28)
    }

    Rectangle {
        id: pill
        x: (win.width - width) / 2
        // Compact faces sit in the middle of the bar (34 px), with as much
        // room above as below; taller ones (a message, the player) hang from
        // the same 2 px inset as the 30 px faces.
        readonly property real band: 34
        y: height <= 30 ? (band - height) / 2 : 2
        width: win.size[0]
        height: win.size[1]
        radius: win.face === "player" ? Theme.rXl : win.size[1] / 2
        Behavior on width { SpringPanel {} }
        Behavior on height { SpringPanel {} }
        Behavior on radius { SpringPanel {} }
        color: win.deep
        border.width: 1
        border.color: Theme.rgba(Theme.islandText, 0.06)
        clip: true

        // The pill itself: open the player from music, read a note, close
        // the player. Controls inside take their own clicks.
        // Hovering the open player holds off flashes (also over its controls).
        HoverHandler { id: hover }
        readonly property bool holding: hover.hovered && win.face === "player"
        onHoldingChanged: if (win.hub && win.output === win.hub.playerScreen) win.hub.hoveringPlayer = holding
        MouseArea {
            anchors.fill: parent
            cursorShape: ["music", "player", "note"].indexOf(win.face) >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (win.face === "music") win.hub.openPlayer(win.output);
                else if (win.face === "player") win.hub.closePlayer();
                else if (win.face === "note") win.hub.openNotifications();
            }
        }

        // ---------------------------------------------------------- idle
        Face {
            on: win.face === "idle"
            width: 96; height: 26
            T {
                anchors.centerIn: parent
                text: Qt.formatTime(clock.date, "HH:mm")
                SystemClock { id: clock; precision: SystemClock.Minutes }
            }
        }

        // ---------------------------------------------------------- music
        Face {
            id: musicFace
            on: win.face === "music"
            width: 230; height: 30
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 12
                spacing: 10
                Item { Layout.preferredWidth: 18; Layout.preferredHeight: 18 }      // the art sits here
                S { text: win.hub ? win.hub.title : "" }
                Eq { playing: win.hub ? win.hub.playing : false }
            }
        }

        // ---------------------------------------------------------- player
        Face {
            id: playerFace
            on: win.face === "player"
            width: 380; height: 168
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    spacing: 14
                    Item { Layout.preferredWidth: 64; Layout.preferredHeight: 64 }  // the art sits here
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2
                        Marquee {
                            Layout.fillWidth: true
                            text: win.hub ? win.hub.title : ""
                            color: Theme.islandText
                            font.pixelSize: Theme.fsL
                            font.weight: Font.DemiBold
                        }
                        S { text: win.hub ? win.hub.artist : ""; visible: text !== "" }
                    }
                    // The output: where the sound goes.
                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        Layout.maximumWidth: 112
                        Layout.preferredWidth: chip.implicitWidth + 16
                        Layout.preferredHeight: 22
                        visible: win.hub && win.hub.device !== ""
                        radius: height / 2
                        color: Theme.rgba(Theme.islandText, 0.1)
                        RowLayout {
                            id: chip
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 8
                            spacing: 6
                            Icon { name: win.hub && win.hub.deviceBluetooth ? "bluetooth" : "speaker"; size: 13; color: Theme.islandText }
                            Label {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: win.hub ? win.hub.device : ""
                                color: Theme.islandText
                                font.pixelSize: 11
                            }
                        }
                    }
                }
                Scrub {
                    Layout.fillWidth: true
                    hub: win.hub
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 18
                    Control { icon: "prev"; onActivated: win.hub.previous() }
                    Control { icon: win.hub && win.hub.playing ? "pause" : "play"; big: true; onActivated: win.hub.toggle() }
                    Control { icon: "next"; onActivated: win.hub.next() }
                }
            }
        }

        // ---------------------------------------------------------- focus
        Face {
            on: win.face === "focus"
            width: 210; height: 30
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 12
                spacing: 10
                Icon { name: "moon"; size: 15; color: Theme.islandText }
                T { text: win.hub ? win.hub.focusClock : "" }
                S { text: "Focus" }
                Ring { progress: win.hub ? win.hub.focusProgress : 0 }
            }
        }

        // ---------------------------------------------------------- recording
        Face {
            on: win.face === "recording"
            width: 260; height: 30
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 5
                spacing: 10
                Rectangle {
                    Layout.preferredWidth: 9; Layout.preferredHeight: 9
                    radius: 4.5
                    color: win.alert
                    SequentialAnimation on opacity {
                        running: win.face === "recording"
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                    }
                }
                T {
                    readonly property int s: win.hub ? win.hub.recSeconds : 0
                    readonly property string mmss: String(Math.floor(s / 60) % 60).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0")
                    text: s >= 3600 ? Math.floor(s / 3600) + ":" + mmss : mmss
                }
                S { text: "Recording" }
                // Stop: ends the recording through the capture script.
                Rectangle {
                    Layout.preferredWidth: 20; Layout.preferredHeight: 20
                    radius: Theme.rXs
                    color: Theme.rgba(Theme.islandText, stopArea.containsMouse ? 0.24 : 0.14)
                    Behavior on color { ColorAnimation { duration: Theme.tQuick } }
                    scale: stopArea.pressed ? 0.9 : 1
                    Behavior on scale { SpringPress {} }
                    Rectangle { anchors.centerIn: parent; width: 7; height: 7; radius: 1.5; color: Theme.islandText }
                    MouseArea {
                        id: stopArea
                        anchors.fill: parent
                        anchors.margins: -5
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.hub.stopRecording()
                    }
                }
            }
        }

        // ---------------------------------------------------------- note
        Face {
            on: win.face === "note"
            width: 300; height: 34
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 14
                spacing: 10
                // Sender: their picture, the app's icon, or an initial.
                Rectangle {
                    Layout.preferredWidth: 18; Layout.preferredHeight: 18
                    radius: Theme.rXs
                    color: noteImage.status === Image.Ready ? Theme.rgba(Theme.islandInk, 0) : Theme.islandInk
                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 1
                        visible: noteImage.status !== Image.Ready
                        text: ((win.held.note.sender || win.held.note.text || "·").trim()[0] || "·").toUpperCase()
                        color: win.deep
                        font.family: Theme.hero; font.weight: Theme.heroWeight
                        font.pixelSize: 15
                    }
                    ClippingRectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"
                        visible: noteImage.status === Image.Ready
                        Image {
                            id: noteImage
                            anchors.fill: parent
                            source: win.held.note.image || win.held.note.icon || ""
                            sourceSize: Qt.size(36, 36)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }
                }
                Label {
                    Layout.maximumWidth: 120
                    Layout.minimumWidth: 0
                    visible: text !== ""
                    text: win.held.note.sender || ""
                    color: Theme.islandText
                    font.pixelSize: Theme.fsS
                    font.weight: Font.DemiBold
                }
                S { text: win.held.note.text || ""; opacity: 0.85 }
            }
        }

        // ---------------------------------------------------------- level
        Face {
            id: levelFace
            on: win.face === "level"
            width: 250; height: 30
            readonly property var p: win.held.level
            readonly property var level: !win.hub || !p.kind ? ({ "kind": "volume", "value": 0, "muted": false })
                : p.live ? win.hub.level(p.kind) : p
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 12
                spacing: 10
                Icon {
                    readonly property var l: levelFace.level
                    name: l.kind === "brightness" ? "sun" : l.kind === "mic" ? "mic" : (l.muted || l.value <= 0 ? "mute" : "speaker")
                    size: 15
                    color: Theme.islandText
                    opacity: l.kind === "mic" && l.muted ? 0.5 : 1
                }
                Item { Layout.fillWidth: true }
                Notches { value: levelFace.level.muted ? 0 : levelFace.level.value }
            }
        }

        // ---------------------------------------------------------- battery
        Face {
            id: batteryFace
            on: win.face === "battery"
            width: win.sizes.battery[0]; height: 30
            readonly property bool low: win.held.battery.kind === "low"
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 12
                spacing: 10
                Icon {
                    name: batteryFace.low ? "battery" : "bolt"
                    size: 15
                    color: batteryFace.low ? win.warm : Theme.islandInk
                }
                T {
                    text: (win.held.battery.percent !== undefined ? win.held.battery.percent : 0) + "%"
                    color: batteryFace.low ? win.warm : Theme.islandText
                }
                S {
                    text: batteryFace.low ? "Battery low · plug in soon" : win.held.battery.kind === "full" ? "Charged" : "Charging"
                    color: batteryFace.low ? win.warm : Theme.islandText
                    opacity: batteryFace.low ? 1 : 0.7
                }
            }
        }

        // ---------------------------------------------------------- layout
        Face {
            on: win.face === "layout"
            width: win.sizes.layout[0]; height: 30
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12; anchors.rightMargin: 14
                spacing: 10
                Icon { name: "keyboard"; size: 15; color: Theme.islandText }
                T {
                    id: layoutName
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: win.held.layout.name || ""
                }
            }
        }

        // ---------------------------------------------------------- the art
        // One cover for the music face and the player: it moves and grows
        // between their slots instead of fading from one to the other.
        Face { id: artFade; on: win.face === "music" || win.face === "player" }
        Cover {
            id: cover
            property real morph: win.face === "player" ? 1 : 0
            Behavior on morph { SpringPanel { epsilon: 0.002 } }
            readonly property real small: 18
            readonly property real big: 64
            readonly property real sx: (pill.width - 230) / 2 + 12
            readonly property real sy: (pill.height - small) / 2
            readonly property real bx: (pill.width - 380) / 2 + 16
            readonly property real by: (pill.height - 168) / 2 + 16
            x: sx + (bx - sx) * morph
            y: sy + (by - sy) * morph
            width: small + (big - small) * morph
            height: width
            radius: Theme.rXs + (Theme.inner(Theme.rXl, 16) - Theme.rXs) * morph
            opacity: artFade.opacity
            visible: opacity > 0.001
            source: win.hub ? win.hub.art : ""
        }
    }

    // A round player control; the middle one is filled.
    component Control: Rectangle {
        id: c
        property string icon
        property bool big: false
        signal activated()
        Layout.preferredWidth: 34
        Layout.preferredHeight: 34
        radius: 17
        color: big ? Theme.islandText : Theme.rgba(Theme.islandText, ctl.containsMouse ? 0.12 : 0)
        Behavior on color { ColorAnimation { duration: Theme.tQuick } }
        scale: ctl.pressed ? 0.92 : 1
        Behavior on scale { SpringPress {} }
        Icon { anchors.centerIn: parent; name: c.icon; size: 20; color: c.big ? win.deep : Theme.islandText }
        MouseArea {
            id: ctl
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: c.activated()
        }
    }
}
