import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// One screen of the lock (workshop/studies/lockscreen/v1.html). The main
// screen: the art on the left, the paper page on the right with the name
// tab, the date and clock, the cross grid and the status foot; the eye on
// the spine and power on the screen's edge. Other screens: the plate alone.
// Unlocking: every cell floods, the page's print lifts, the paper slides
// aside and the art opens out into the desktop's own plate.
FocusScope {
    id: root
    required property var lock
    required property var auth
    required property bool main

    readonly property var fx: lock.fx
    readonly property bool opening: lock.phase === "opening"
    readonly property real share: 0.56
    readonly property real gentle: 0.6 * Art.breathe
    property real artFrac: main ? share : 1
    property real slide: 0                  // 0 in place, 1 off the right edge
    property real chrome: 1                 // edge tabs and caption

    focus: true
    Component.onCompleted: forceActiveFocus()
    Keys.onPressed: event => {
        event.accepted = true;
        if (power.key(event)) return;
        root.lock.key(event);
    }

    // The status, live or from a fixture.
    readonly property string userName: fx ? fx.name : lock.userName
    readonly property string ssid: fx ? fx.ssid : Network.wired ? "Wired" : Network.ssid
    readonly property int battery: fx ? fx.battery : Battery.present ? Battery.percent : -1
    readonly property string layout: fx ? fx.layout : shortLayout(Niri.layoutName)
    readonly property string songTitle: fx ? fx.title : Media.active ? Media.title : ""
    readonly property string songArtist: fx ? fx.artist : Media.artist
    readonly property bool songPlaying: fx ? fx.playing : Media.playing
    readonly property bool fingerprint: root.auth.fingerprint
    function shortLayout(name) {
        if (!name) return "";
        const m = name.match(/\(([^)]{1,4})\)/);
        return m ? m[1].toUpperCase() : name.slice(0, 2).toUpperCase();
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property var esAR: Qt.locale("es_AR")

    // The art.
    Plate {
        id: plate
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
        width: root.width * root.artFrac
        portrait: root.main
        breathe: root.gentle
    }
    // The desktop's composition of the same plate, dissolved in as the art
    // opens out, so the lock hands over to the wallpaper without a seam.
    Image {
        id: desk
        visible: false; asynchronous: true; mipmap: true; smooth: true
        source: root.main ? Art.mask(Art.current) : ""
    }

    Item {
        id: caption
        visible: root.main
        opacity: root.chrome
        x: 20
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        width: Math.min(creditText.implicitWidth + 22, root.width * root.share - 40)
        height: creditText.implicitHeight + 14
        Frost { anchors.fill: parent; source: plate; radius: 10 }
        Sheet { anchors.fill: parent; radius: 10; color: Theme.sheetStrong }
        Cap {
            id: creditText
            color: Theme.text2
            anchors.fill: parent
            anchors.leftMargin: 11; anchors.rightMargin: 11
            verticalAlignment: Text.AlignVCenter
            text: {
                const p = Art.plate(Art.current);
                return p ? p.title + " · " + p.credit : "";
            }
        }
    }

    // The page.
    Item {
        id: page
        visible: root.main
        x: root.width * root.share + root.slide * width * 1.04
        width: root.width - root.width * root.share
        height: root.height
        readonly property real pad: Math.max(28, Math.min(72, root.width * 0.045))

        RectangularShadow {
            anchors.fill: parent
            offset: Qt.vector2d(-30, 0)
            blur: 60
            color: Theme.rgba(Theme.shade, 0.12)
        }
        Rectangle { anchors.fill: parent; color: Theme.paper }
        Rectangle { x: -1; width: 1; height: parent.height; color: Theme.rule }

        Develop {
            id: pageInk
            anchors.fill: parent
            progress: 0
            grain: 1.4

            // The name tab hangs from the top edge.
            Rectangle {
                id: tab
                anchors.horizontalCenter: parent.horizontalCenter
                width: tabRow.implicitWidth + 44
                height: 39
                color: Theme.ink
                bottomLeftRadius: Theme.rM
                bottomRightRadius: Theme.rM
                Row {
                    id: tabRow
                    x: 22
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 0.5
                    spacing: 10
                    Icon { name: "user"; size: 16; color: Theme.inkText; anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        text: root.userName || "Locked"
                        color: Theme.inkText
                        font.pixelSize: 15
                        font.weight: Font.Medium
                        width: Math.min(implicitWidth, 320, page.width - 2 * page.pad - 70)
                    }
                }
            }

            // Date, clock, rule and the entry, centred between tab and foot;
            // with notifications waiting, the entry moves up and they take
            // the room under it.
            Item {
                id: middle
                anchors { top: tab.bottom; bottom: foot.top; left: parent.left; right: parent.right; leftMargin: page.pad; rightMargin: page.pad }
                readonly property real edge: Math.max(20, height * 0.05)
                readonly property real notesWant: waiting.naturalHeight > 0 ? waiting.naturalHeight + center.gap : 0
                Column {
                    id: center
                    width: parent.width
                    y: Math.max(middle.edge, (middle.height - height - middle.notesWant) / 2)
                    Behavior on y { SpringPanel {} }
                    readonly property real gap: Math.max(22, Math.min(40, root.height * 0.04))

                    Cap {
                        width: parent.width
                        text: root.esAR.toString(clock.date, "dddd, d 'de' MMMM")
                    }
                    Item { width: 1; height: 6 }
                    // A line box of 0.78 em with the glyphs centred in it, as
                    // CSS sets the study's clock; the figures may overhang it.
                    Item {
                        id: clockBox
                        readonly property real size: Math.max(110, Math.min(200, root.width * 0.13))
                        width: clockText.implicitWidth
                        height: size * 0.78
                        PrintText {
                            id: clockText
                            x: -6
                            y: (clockBox.height - implicitHeight) / 2
                            text: Qt.formatTime(clock.date, "HH:mm")
                            color: Theme.ink
                            font.family: Theme.hero
                            font.pixelSize: clockBox.size
                            font.features: { "tnum": 1 }
                        }
                    }
                    Item { width: 1; height: center.gap }
                    Rectangle { width: parent.width; height: 1; color: Theme.ruleStrong }
                    Item { width: 1; height: center.gap }

                    Row {
                        width: parent.width
                        spacing: 28
                        CrossGrid {
                            id: grid
                            anchors.verticalCenter: parent.verticalCenter
                            cell: Math.max(30, Math.min(44, root.width * 0.032))
                            count: root.lock.shown
                            text: root.lock.buffer
                            peek: root.lock.peek
                        }
                        Column {
                            id: how
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - grid.width - 28
                            spacing: 10
                            Row {
                                spacing: 10
                                Icon { name: "keyboard"; size: 20; color: Theme.ink; anchors.verticalCenter: parent.verticalCenter }
                                Label { text: "Type your password"; color: Theme.text2; width: Math.min(implicitWidth, how.width - 30) }
                            }
                            Row {
                                visible: root.fingerprint
                                spacing: 10
                                Icon {
                                    name: "fingerprint"; size: 20; color: Theme.ink
                                    anchors.verticalCenter: parent.verticalCenter
                                    SequentialAnimation on opacity {
                                        running: root.fingerprint && root.visible; loops: Animation.Infinite
                                        NumberAnimation { to: 0.35; duration: 1300; easing.type: Easing.InOutCubic }
                                        NumberAnimation { to: 1; duration: 1300; easing.type: Easing.InOutCubic }
                                    }
                                }
                                Label { text: "or touch the sensor"; color: Theme.text2; width: Math.min(implicitWidth, how.width - 30) }
                            }
                            Label {
                                width: how.width
                                height: Math.max(20, implicitHeight)
                                text: root.lock.phase === "checking" ? "Checking…" : root.lock.message
                                color: root.lock.messageError ? Theme.error : Theme.text3
                                font.weight: Font.Medium
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                            }
                            Cap { visible: root.lock.harness; text: "Try “folio”" }
                        }
                    }
                }
                LockNotes {
                    id: waiting
                    lock: root.lock
                    y: center.y + center.height + center.gap
                    width: Math.min(parent.width, 620)
                    maxHeight: Math.max(0, middle.height - y - middle.edge * 0.5)
                }
            }

            // Status and what's playing.
            Item {
                id: foot
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: page.pad; rightMargin: page.pad }
                height: Math.max(statusRow.implicitHeight, mini.implicitHeight) + 40
                Rectangle { width: parent.width; height: 1; color: Theme.rule }
                RowLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 18 }
                    height: Math.max(statusRow.implicitHeight, mini.implicitHeight)
                    spacing: 14
                    Row {
                        id: statusRow
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 16
                        clip: true
                        Repeater {
                            model: [
                                { "icon": "wifi", "text": root.ssid },
                                { "icon": "battery", "text": root.battery >= 0 ? root.battery + "%" : "" },
                                { "icon": "keyboard", "text": root.layout }
                            ].filter(s => s.text)
                            Row {
                                required property var modelData
                                spacing: 6
                                Icon { name: modelData.icon; size: 14; color: Theme.text3; anchors.verticalCenter: parent.verticalCenter }
                                Cap { text: modelData.text; width: Math.min(implicitWidth, 220); anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }
                    RowLayout {
                        id: mini
                        visible: root.songTitle !== ""
                        spacing: 10
                        Layout.maximumWidth: 260
                        Rectangle {
                            implicitWidth: 34; implicitHeight: 34; radius: 17
                            color: Theme.ink
                            scale: playArea.pressed ? 0.95 : 1
                            Behavior on scale { SpringPress {} }
                            Icon { anchors.centerIn: parent; size: 18; name: root.songPlaying ? "pause" : "play"; color: Theme.inkText }
                            MouseArea { id: playArea; anchors.fill: parent; onClicked: if (!root.fx) Media.toggle() }
                        }
                        ColumnLayout {
                            spacing: 1
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Marquee {
                                Layout.fillWidth: true
                                Layout.maximumWidth: 210
                                Layout.preferredWidth: implicitWidthHint
                                readonly property real implicitWidthHint: Math.min(210, titleMetrics.advanceWidth + 2)
                                text: root.songTitle
                                font.pixelSize: Theme.fsS
                                font.weight: Font.DemiBold
                            }
                            Label {
                                Layout.fillWidth: true
                                Layout.maximumWidth: 210
                                text: root.songArtist
                                color: Theme.text2
                                font.pixelSize: 12
                            }
                        }
                        TextMetrics { id: titleMetrics; text: root.songTitle; font.family: Theme.ui; font.pixelSize: Theme.fsS; font.weight: Font.DemiBold }
                    }
                }
            }
        }
    }

    // The eye on the spine: hold to read the cells.
    Rectangle {
        visible: root.main
        opacity: root.chrome
        x: page.x
        anchors.verticalCenter: parent.verticalCenter
        width: 38; height: 64
        color: Theme.ink
        topRightRadius: Theme.rM; bottomRightRadius: Theme.rM
        Icon { anchors.centerIn: parent; name: "eye"; size: 20; color: Theme.inkText }
        MouseArea {
            anchors.fill: parent
            enabled: !root.opening
            onPressedChanged: root.lock.peek = pressed
        }
    }

    // Power on the screen's edge: hold 1.2 s, then Hibernate or Shut down.
    LockPower {
        id: power
        visible: root.main
        opacity: root.chrome
        anchors.fill: parent
        lock: root.lock
        enabled: !root.opening
    }

    // Arrival: the page prints in after the plate starts developing.
    Timer { running: root.main; interval: Math.max(1, 500 * Theme.motion); onTriggered: pageInk.printIn(700) }

    onOpeningChanged: if (opening) openAnim.start()
    function dissolve() {
        if (!root.main || desk.status !== Image.Ready) return;
        plate.sourceB = desk;
        plate.focusB = Art.focus(Art.current);
        plate.zoomB = 1;
        plate.mixAB = 0;
        dissolveAnim.start();
    }
    SequentialAnimation {
        id: openAnim
        ScriptAction { script: { grid.flood(); power.close(); } }
        PauseAnimation { duration: Math.max(1, 410 * Theme.motion) }
        ScriptAction { script: { pageInk.lift(380); root.dissolve(); } }
        ParallelAnimation {
            Ease { target: root; property: "artFrac"; to: 1; duration: 900 * Theme.motion }
            NumberAnimation { target: plate; property: "breathe"; to: Art.breathe; duration: 900 * Theme.motion }
            NumberAnimation { target: root; property: "chrome"; to: 0; duration: 300 * Theme.motion }
            SequentialAnimation {
                PauseAnimation { duration: Math.max(1, 240 * Theme.motion) }
                Ease { target: root; property: "slide"; to: 1; duration: 760 * Theme.motion }
            }
        }
    }
    NumberAnimation {
        id: dissolveAnim
        target: plate; property: "mixAB"; from: 0; to: 1; duration: 700 * Theme.motion
        easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1]
    }

    Connections {
        target: root.lock
        function onRefused() { grid.shake(); }
        function onPowerChoices() { if (root.main) power.menu = true; }
    }
}
