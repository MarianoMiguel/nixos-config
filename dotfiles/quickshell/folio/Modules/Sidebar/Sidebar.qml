import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// The sidebar: today, the quick controls and what is waiting, as one page of
// widgets on the focused screen. It turns in from the screen edge like a
// leaf hinged at its spine while its rows follow 34 ms apart (the cascade);
// closing mirrors it, and a reversal mid-turn keeps its velocity (spring).
// Esc or a click outside closes it. It stops above the dock's band.
Scope {
    id: root

    readonly property bool open: Shell.sidebarOpen
    readonly property bool onLeft: Settings.get("sidebar.side") === "left"
    readonly property real sheetWidth: 380
    readonly property real top: 42
    readonly property real bottom: 88       // the dock's band stays clear
    readonly property real gap: 8
    readonly property real radius: 26
    readonly property real pad: 14
    // The focused screen, followed only while closed so an open sidebar
    // never jumps between outputs.
    readonly property var focusedScreen: Shell.screenFor(Quickshell.screens)
    property var screen: null
    onFocusedScreenChanged: if (!shown) screen = focusedScreen
    Component.onCompleted: screen = focusedScreen
    onShownChanged: if (!shown) screen = focusedScreen

    // The leaf: 0 closed, 100 open, on the panel spring.
    property real leaf: open ? 100 : 0
    Behavior on leaf { enabled: Settings.motion > 0.1; SpringPanel {} }
    readonly property bool shown: open || leaf > 0.5
    readonly property bool settled: open && leaf > 99

    // The cascade's clock, in ms at full motion: row i arrives over 460 ms
    // from 120 + 34 i. Closing runs it back three times as fast.
    property real wave: 0
    readonly property int rows: 12
    readonly property real waveEnd: 120 + rows * 34 + 460
    NumberAnimation { id: waveAnim; target: root; property: "wave" }
    function step(i) {
        const t = Math.max(0, Math.min(1, (wave - 120 - i * 34) / 460));
        return 1 - Math.pow(1 - t, 4);
    }
    function rise(i) { return 12 * (1 - step(i)); }

    onOpenChanged: {
        waveAnim.stop();
        waveAnim.to = open ? waveEnd : 0;
        waveAnim.duration = Math.max(1, (open ? waveEnd - wave : wave / 3) * Settings.motion);
        waveAnim.start();
        if (open) {
            Tailscale.refresh();
            revealTimer.restart();
        }
    }

    // A leaf turning about its spine with perspective (the kit's
    // perspective(1600px) translateX(36px) rotateY(-16deg) scale(0.98)).
    // Depth is squeezed afterwards so nothing reaches the near plane; at
    // rest it is the identity, so text and shapes render as plain 2D.
    function leafMatrix(p, w, h, left) {
        if (Math.abs(p - 1) < 0.001) return Qt.matrix4x4();
        p = Math.max(0, Math.min(1.02, p));
        const q = 1 - p, ox = left ? 0 : w, oy = h / 2;
        const a = (left ? 16 : -16) * q * Math.PI / 180, c = Math.cos(a), s = Math.sin(a);
        const k = 0.98 + 0.02 * p, tx = (left ? -36 : 36) * q;
        const T = (x, y) => Qt.matrix4x4(1, 0, 0, x, 0, 1, 0, y, 0, 0, 1, 0, 0, 0, 0, 1);
        const P = Qt.matrix4x4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, -1 / 1600, 1);
        const R = Qt.matrix4x4(c, 0, s, 0, 0, 1, 0, 0, -s, 0, c, 0, 0, 0, 0, 1);
        const S = Qt.matrix4x4(k, 0, 0, 0, 0, k, 0, 0, 0, 0, k, 0, 0, 0, 0, 1);
        const m = T(ox, oy).times(P).times(T(tx, 0)).times(R).times(S).times(T(-ox, -oy));
        const z = 0.001;
        return Qt.matrix4x4(m.m11, m.m12, m.m13, m.m14, m.m21, m.m22, m.m23, m.m24, m.m31 * z, m.m32 * z, m.m33 * z, m.m34 * z, m.m41, m.m42, m.m43, m.m44);
    }

    // Sections (IPC open(section)): scroll there and open what belongs to it.
    Timer { id: revealTimer; interval: 40; onTriggered: root.reveal(Shell.sidebarSection) }
    function reveal(section) {
        tiles.show(section === "wifi" || section === "bluetooth" ? section : "");
        sliders.outputsOpen = section === "audio";
        power.open = section === "power";
        notes.showAll = false;
        notes.expanded = ({});
        const target = ({ "wifi": tiles, "bluetooth": tiles, "audio": sliders, "music": music, "world": worldHead,
                          "calendar": calendar, "focus": focusCard, "quota": quotaHead, "notifications": notes, "power": footer })[section];
        if (!target) { glide = false; follow = null; flick.contentY = 0; return; }
        scrollTo(target);
    }
    // Programmatic scrolls glide on a spring (a Behavior, so a new aim keeps
    // the velocity) and follow their target while drawers above it spring
    // open or shut, so they land where it ends up. Touching the page stops it.
    property bool glide: false
    property Item follow: null
    property real aim: 0
    readonly property real followY: follow ? clampY(follow.y - 2) : -1
    onFollowYChanged: if (follow && glide) flick.contentY = followY
    Timer { id: glideEnd; interval: 900; onTriggered: { root.glide = false; root.follow = null; } }
    function scrollTo(item) { follow = item; glide = true; glideEnd.restart(); flick.contentY = followY; }
    function scrollBy(dy) {
        aim = clampY((glide ? aim : flick.contentY) + dy);
        follow = null; glide = true; glideEnd.restart();
        flick.contentY = aim;
    }
    function clampY(y) { return Math.max(0, Math.min(y, flick.contentHeight - flick.height)); }

    Feed {
        id: feed
        ticking: root.shown
        onCloseRequested: Shell.sidebarOpen = false
    }

    PanelWindow {
        id: win
        screen: root.screen || Quickshell.screens[0] || null
        visible: root.shown
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "folio:sidebar"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        // While closing, clicks already pass through to what is behind.
        mask: Region { item: root.open ? catcher : null }
        // Frost where the sheet lands, from a third of the way in (the curl
        // itself cannot be a region, so the region follows an untransformed
        // stand-in) until it starts to leave. The region stays and goes empty
        // rather than being swapped for null, which left frost behind.
        readonly property bool frosted: root.open && root.leaf > 35
        BackgroundEffect.blurRegion: Region { item: win.frosted ? landing : null; radius: root.radius + frost.extra }
        BlurNudge { id: frost; key: win.frosted }
        Item { id: landing; x: page.x; y: page.y; width: page.width; height: page.height }

        // Outside the sheet: a click closes.
        MouseArea {
            id: catcher
            anchors.fill: parent
            onClicked: Shell.sidebarOpen = false
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    if (power.open) power.open = false; else Shell.sidebarOpen = false;
                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_PageDown || event.key === Qt.Key_Up || event.key === Qt.Key_PageUp) {
                    root.scrollBy((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp ? flick.height * 0.8 : 60) * (event.key === Qt.Key_Up || event.key === Qt.Key_PageUp ? -1 : 1));
                } else return;
                event.accepted = true;
            }
        }

        Item {
            id: page
            x: root.onLeft ? root.gap : parent.width - root.sheetWidth - root.gap
            y: root.top
            width: root.sheetWidth
            height: Math.max(200, parent.height - root.top - root.bottom)
            opacity: Math.max(0, Math.min(1, root.leaf / 100))
            transform: Matrix4x4 { matrix: root.leafMatrix(root.leaf / 100, page.width, page.height, root.onLeft) }

            Sheet {
                id: sheet
                anchors.fill: parent
                radius: root.radius

                // Clicks on the sheet stay on it.
                MouseArea { anchors.fill: parent }

                Flickable {
                    id: flick
                    anchors.fill: parent
                    anchors.margins: root.pad
                    anchors.bottomMargin: root.pad - 4
                    contentWidth: width
                    contentHeight: column.implicitHeight + 4
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    onMovementStarted: { root.glide = false; root.follow = null; power.open = false; }
                    // Content that shrinks under the end pulls the page down with it.
                    onContentHeightChanged: if (!root.glide && !moving && contentY > root.clampY(contentY)) contentY = root.clampY(contentY)
                    Behavior on contentY { enabled: root.glide; SpringPanel {} }

                    ColumnLayout {
                        id: column
                        width: flick.width
                        spacing: 10

                        HeroCard {
                            feed: feed
                            printing: root.settled
                            Layout.fillWidth: true
                            opacity: root.step(0)
                            transform: Translate { y: root.rise(0) }
                        }
                        TilesCard {
                            id: tiles
                            feed: feed
                            Layout.fillWidth: true
                            opacity: root.step(1)
                            transform: Translate { y: root.rise(1) }
                        }
                        SlidersCard {
                            id: sliders
                            feed: feed
                            Layout.fillWidth: true
                            opacity: root.step(2)
                            transform: Translate { y: root.rise(2) }
                        }
                        MusicCard {
                            id: music
                            feed: feed
                            Layout.fillWidth: true
                            opacity: root.step(3)
                            transform: Translate { y: root.rise(3) }
                        }
                        SectionHead {
                            id: worldHead
                            title: "World clock"
                            Layout.fillWidth: true
                            opacity: root.step(4)
                            transform: Translate { y: root.rise(4) }
                        }
                        WorldCard {
                            feed: feed
                            Layout.fillWidth: true
                            opacity: root.step(5)
                            transform: Translate { y: root.rise(5) }
                        }
                        CalendarCard {
                            id: calendar
                            feed: feed
                            Layout.fillWidth: true
                            opacity: root.step(6)
                            transform: Translate { y: root.rise(6) }
                        }
                        FocusCard {
                            id: focusCard
                            feed: feed
                            Layout.fillWidth: true
                            opacity: root.step(7)
                            transform: Translate { y: root.rise(7) }
                        }
                        SectionHead {
                            id: quotaHead
                            visible: feed.quota.length > 0
                            title: "AI quota"
                            note: "CodexBar"
                            Layout.fillWidth: true
                            opacity: root.step(8)
                            transform: Translate { y: root.rise(8) }
                        }
                        QuotaCard {
                            visible: feed.quota.length > 0
                            feed: feed
                            Layout.fillWidth: true
                            opacity: root.step(9)
                            transform: Translate { y: root.rise(9) }
                        }
                        NotesCard {
                            id: notes
                            feed: feed
                            Layout.fillWidth: true
                            opacity: root.step(10)
                            transform: Translate { y: root.rise(10) }
                        }
                        FooterBar {
                            id: footer
                            feed: feed
                            powerOpen: power.open
                            Layout.fillWidth: true
                            Layout.topMargin: -4
                            opacity: root.step(11)
                            transform: Translate { y: root.rise(11) }
                            onPowerClicked: power.open = !power.open
                        }
                    }
                }

                // The power menu floats over the page; a click elsewhere on
                // the sheet closes it.
                MouseArea {
                    anchors.fill: parent
                    visible: power.open
                    onClicked: power.open = false
                }
                PowerMenu {
                    id: power
                    // Over the Power button, wherever the page has scrolled.
                    x: root.pad + footer.x + footer.powerButton.x + footer.powerButton.width - width
                    y: root.pad + footer.y - flick.contentY + footer.powerButton.y - height - 8
                    onChosen: what => { power.open = false; feed.power(what); }
                }
            }
        }
    }

    IpcHandler {
        target: "sidebar"
        function toggle(): void { Shell.toggleSidebar(""); }
        // Sections: wifi, bluetooth, audio, music, world, calendar, focus,
        // quota, notifications, power ("" for the top).
        function open(section: string): void {
            if (!Shell.sidebarOpen) { Shell.toggleSidebar(section); return; }
            Shell.sidebarSection = section;
            root.reveal(section);
        }
        function close(): void { Shell.sidebarOpen = false; }
        // normal | stress | empty, or live for the real services.
        function fixture(name: string): void { feed.fixture = name === "live" ? "" : name; }
    }
}
