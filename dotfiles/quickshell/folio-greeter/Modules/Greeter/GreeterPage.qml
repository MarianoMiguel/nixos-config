import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// One screen of the login: the lock screen's composition (the art on the
// left, the paper page on the right with the name tab, the date and clock,
// the cross grid and the status foot; the eye on the spine, power on the
// edge), plus the session under the entry and a line of key hints. Type is
// larger than the lock's and nothing relies on blur: it has to read on a
// KVM's compressed capture. Signing in plays the lock's opening: the cells
// flood, the print lifts, the paper slides aside and the art opens out.
FocusScope {
    id: root
    required property var greeter
    readonly property var g: greeter
    readonly property var fx: g.fx

    readonly property bool opening: g.phase !== "typing"
    readonly property bool wide: width > height * 1.1
    readonly property real share: wide ? 0.56 : 0.34
    readonly property real gentle: 0.6 * Settings.get("plates.breathe")
    property real artFrac: share
    property real slide: 0
    property real chrome: 1

    focus: true
    Component.onCompleted: forceActiveFocus()
    Keys.onPressed: event => {
        event.accepted = true;
        if (power.key(event)) return;
        root.g.key(event);
    }

    readonly property string userName: g.user.real || g.user.name || ""
    readonly property int battery: fx ? fx.battery : Battery.present ? Battery.percent : -1
    readonly property string layout: fx ? fx.layout : shortLayout(Niri.layoutName)
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
        plate: root.g.plate
        portrait: true
        breathe: root.gentle
    }
    Item {
        id: caption
        opacity: root.chrome
        x: 22
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        width: Math.min(creditText.implicitWidth + 26, root.width * root.share - 44)
        height: creditText.implicitHeight + 16
        visible: creditText.text !== ""
        Sheet { anchors.fill: parent; radius: 10; color: Theme.sheetStrong; shadow: false }
        Cap {
            id: creditText
            color: Theme.text2
            font.pixelSize: 12
            anchors.fill: parent
            anchors.leftMargin: 13; anchors.rightMargin: 13
            verticalAlignment: Text.AlignVCenter
            text: {
                const p = Art.plate(root.g.plate);
                return p ? p.title + " · " + p.credit : "";
            }
        }
    }

    // A ring around whatever the keyboard is on.
    component Ring: Rectangle {
        property bool on: false
        property real r: Theme.rM
        anchors.fill: parent
        anchors.margins: -5
        radius: r + 5
        color: "transparent"
        border.width: 2
        border.color: Theme.ink
        opacity: on ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.tQuick } }
    }

    // The page.
    Item {
        id: page
        x: root.width * root.share + root.slide * width * 1.04
        width: root.width - root.width * root.share
        height: root.height
        readonly property real pad: Math.max(28, Math.min(80, root.width * 0.045))

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

            // The name tab hangs from the top edge: the avatar, the name and,
            // with more than one user, the arrows to the others.
            Rectangle {
                id: tab
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(tabRow.implicitWidth + 40, page.width - 2 * page.pad)
                height: 50
                color: Theme.ink
                bottomLeftRadius: Theme.rM
                bottomRightRadius: Theme.rM
                readonly property bool several: root.g.users.length > 1
                Ring { on: root.g.focusPart === "user"; r: Theme.rM; anchors.topMargin: -20 }
                Row {
                    id: tabRow
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 1
                    spacing: 12
                    Icon { visible: tab.several; name: "back"; size: 16; color: Theme.inkText; anchors.verticalCenter: parent.verticalCenter }
                    ClippingRectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32; height: 32
                        radius: 16
                        color: Theme.inkText
                        Image {
                            id: avatar
                            anchors.fill: parent
                            source: root.g.user.avatar ? "file://" + root.g.user.avatar : ""
                            sourceSize: Qt.size(64, 64)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: status === Image.Ready
                        }
                        Text {
                            visible: !avatar.visible
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 1
                            text: (root.userName || "?").charAt(0).toUpperCase()
                            color: Theme.ink
                            font.family: Theme.hero
                            font.pixelSize: 22
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.userName || "Sign in"
                        color: Theme.inkText
                        font.pixelSize: 18
                        font.weight: Font.Medium
                        width: Math.min(implicitWidth, page.width - 2 * page.pad - 40 - 44 - (tab.several ? 56 : 0))
                    }
                    Icon { visible: tab.several; name: "right"; size: 16; color: Theme.inkText; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: tab.several && !root.opening
                    onClicked: mouse => { root.g.focusPart = "user"; root.g.chooseUser(root.g.userIndex + (mouse.x < width / 2 ? -1 : 1)); }
                }
            }

            // Date, clock, rule, the entry and the session, centred between
            // the tab and the foot.
            Item {
                anchors { top: tab.bottom; bottom: foot.top; left: parent.left; right: parent.right; leftMargin: page.pad; rightMargin: page.pad }
                Column {
                    id: center
                    width: parent.width
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property real gap: Math.max(22, Math.min(40, root.height * 0.04))

                    Cap {
                        width: parent.width
                        text: root.esAR.toString(clock.date, "dddd, d 'de' MMMM")
                        color: Theme.text2
                        font.pixelSize: 14
                    }
                    Item { width: 1; height: 8 }
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
                        spacing: 30
                        CrossGrid {
                            id: grid
                            anchors.verticalCenter: parent.verticalCenter
                            cell: Math.max(32, Math.min(46, root.width * 0.033))
                            count: root.g.shown
                            text: root.g.buffer
                            peek: root.g.peek
                            caret: root.g.focusPart === "password"
                        }
                        Column {
                            id: how
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - grid.width - 30
                            spacing: 12
                            Row {
                                spacing: 12
                                Icon { name: "keyboard"; size: 22; color: Theme.ink; anchors.verticalCenter: parent.verticalCenter }
                                Label {
                                    text: root.g.login.question || "Type your password"
                                    color: Theme.text
                                    font.pixelSize: 17
                                    width: Math.min(implicitWidth, how.width - 34)
                                }
                            }
                            Row {
                                visible: root.g.login.listening || root.g.login.fingerSeen
                                spacing: 12
                                Icon {
                                    name: "fingerprint"; size: 22; color: Theme.ink
                                    anchors.verticalCenter: parent.verticalCenter
                                    opacity: root.g.login.listening ? 1 : 0.45
                                    SequentialAnimation on opacity {
                                        running: root.g.login.listening && root.visible; loops: Animation.Infinite
                                        NumberAnimation { to: 0.35; duration: 1300; easing.type: Easing.InOutCubic }
                                        NumberAnimation { to: 1; duration: 1300; easing.type: Easing.InOutCubic }
                                    }
                                }
                                Label {
                                    text: root.g.login.listening ? "or touch the sensor" : "Esc, then touch the sensor"
                                    color: Theme.text2
                                    font.pixelSize: 17
                                    width: Math.min(implicitWidth, how.width - 34)
                                }
                            }
                            Label {
                                width: how.width
                                height: Math.max(22, implicitHeight)
                                text: root.g.checking && !root.g.messageError ? "Checking…" : root.g.message
                                color: root.g.messageError ? Theme.error : Theme.text2
                                font.pixelSize: 16
                                font.weight: Font.Medium
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                            }
                            Cap { visible: root.g.harness; text: "Try “folio”"; font.pixelSize: 12 }
                        }
                    }

                    Item { width: 1; height: center.gap }
                    // No session to start: say so, and how to get out.
                    Label {
                        visible: root.g.sessions.length === 0 && (root.g.sessionsRead || root.fx !== null)
                        width: parent.width
                        text: "No sessions are installed. Ctrl+Alt+F2 opens a text console."
                        color: Theme.warning
                        font.pixelSize: 16
                        font.weight: Font.Medium
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                    }
                    // The session: Tab to it, the arrows change it.
                    Item {
                        id: pill
                        visible: root.g.sessions.length > 0
                        readonly property bool focused: root.g.focusPart === "session"
                        readonly property bool several: root.g.sessions.length > 1
                        width: Math.min(parent.width, pillRow.implicitWidth + 36)
                        height: 52
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.rM
                            color: pill.focused ? Theme.wash : "transparent"
                            border.width: 1
                            border.color: Theme.ruleStrong
                        }
                        Ring { on: pill.focused; r: Theme.rM }
                        Row {
                            id: pillRow
                            x: 18
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12
                            Icon { name: "display"; size: 20; color: Theme.ink; anchors.verticalCenter: parent.verticalCenter }
                            Cap { id: sessionCap; text: "Session"; font.pixelSize: 13; color: Theme.text2; anchors.verticalCenter: parent.verticalCenter }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.g.session ? root.g.session.name : ""
                                font.pixelSize: 17
                                font.weight: Font.Medium
                                width: Math.min(implicitWidth, center.width - 36 - 20 - sessionCap.implicitWidth - 3 * 12 - (pill.several ? 2 * 16 + 2 * 12 : 0))
                            }
                            Icon { visible: pill.several; name: "back"; size: 16; color: pill.focused ? Theme.ink : Theme.text3; anchors.verticalCenter: parent.verticalCenter }
                            Icon { visible: pill.several; name: "right"; size: 16; color: pill.focused ? Theme.ink : Theme.text3; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: pill.several && !root.opening
                            onClicked: { root.g.focusPart = "session"; root.g.chooseSession(root.g.sessionIndex + 1); }
                        }
                    }
                }
            }

            // Status and the keys.
            Item {
                id: foot
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: page.pad; rightMargin: page.pad }
                height: 70
                Rectangle { width: parent.width; height: 1; color: Theme.rule }
                RowLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 22 }
                    spacing: 18
                    // The status keeps its room; the hint gives way.
                    Row {
                        id: statusRow
                        Layout.preferredWidth: Math.min(implicitWidth, foot.width * 0.55)
                        Layout.maximumWidth: Layout.preferredWidth
                        spacing: 18
                        clip: true
                        Repeater {
                            model: [
                                { "icon": "laptop", "text": root.g.host },
                                { "icon": "battery", "text": root.battery >= 0 ? root.battery + "%" : "" },
                                { "icon": "keyboard", "text": root.layout }
                            ].filter(s => s.text)
                            Row {
                                required property var modelData
                                spacing: 7
                                Icon { name: modelData.icon; size: 16; color: Theme.text2; anchors.verticalCenter: parent.verticalCenter }
                                Cap { text: modelData.text; color: Theme.text2; font.pixelSize: 13; width: Math.min(implicitWidth, 260); anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        horizontalAlignment: Text.AlignRight
                        color: Theme.text2
                        font.pixelSize: 15
                        text: {
                            const f = root.g.focusPart;
                            if (f === "power") return root.g.powerMenu ? "↑ ↓ choose · Enter · Esc closes" : "Enter: restart or shut down · Tab: next";
                            if (f === "user" || f === "session") return "← → change · Enter: back to the password";
                            const more = [].concat(root.g.users.length > 1 ? ["user"] : [], root.g.sessions.length > 1 ? ["session"] : [], ["power"]);
                            return "Tab: " + more.join(", ");
                        }
                    }
                }
            }
        }
    }

    // The eye on the spine: hold to read the cells.
    Rectangle {
        opacity: root.chrome
        x: page.x
        anchors.verticalCenter: parent.verticalCenter
        width: 44; height: 72
        color: Theme.ink
        topRightRadius: Theme.rM; bottomRightRadius: Theme.rM
        Icon { anchors.centerIn: parent; name: "eye"; size: 22; color: Theme.inkText }
        MouseArea {
            anchors.fill: parent
            enabled: !root.opening
            onPressedChanged: root.g.peek = pressed
        }
    }

    GreeterPower {
        id: power
        opacity: root.chrome
        anchors.fill: parent
        greeter: root.g
        enabled: !root.opening
    }

    // Arrival: the page prints in after the plate starts developing.
    Timer { id: arrive; running: true; interval: Math.max(1, 500 * Theme.motion); onTriggered: pageInk.printIn(700) }

    onOpeningChanged: if (opening) openAnim.start()
    SequentialAnimation {
        id: openAnim
        ScriptAction { script: grid.flood() }
        PauseAnimation { duration: Math.max(1, 410 * Theme.motion) }
        ScriptAction { script: pageInk.lift(380) }
        ParallelAnimation {
            Ease { target: root; property: "artFrac"; to: 1; duration: 900 * Theme.motion }
            NumberAnimation { target: plate; property: "breathe"; to: Settings.get("plates.breathe"); duration: 900 * Theme.motion }
            NumberAnimation { target: root; property: "chrome"; to: 0; duration: 300 * Theme.motion }
            SequentialAnimation {
                PauseAnimation { duration: Math.max(1, 240 * Theme.motion) }
                Ease { target: root; property: "slide"; to: 1; duration: 760 * Theme.motion }
            }
        }
    }
    // Back to the start (the harness, after a pretend launch; fixtures).
    function reset() {
        openAnim.stop();
        grid.reset();
        artFrac = share;
        slide = 0;
        chrome = 1;
        plate.breathe = gentle;
        pageInk.progress = 1;
    }

    Connections {
        target: root.g
        function onRefused() { grid.shake(); }
        function onResetPages() { root.reset(); }
    }
}
