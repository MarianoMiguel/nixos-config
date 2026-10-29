import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// Now playing: the real cover (the plate when there is none), the title
// gliding when it is long, the artist, the output, a scrub bar that seeks on
// click, and the transport. Empty: "Nothing playing", with the last player
// to resume when there is one.
SideCard {
    id: root
    required property var feed
    readonly property var m: feed.media

    implicitHeight: m.active ? player.implicitHeight + 28 : empty.implicitHeight + 36

    // Playing or paused
    ColumnLayout {
        id: player
        visible: root.m.active
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            ClippingRectangle {
                implicitWidth: 92
                implicitHeight: 92
                radius: Theme.rS
                color: Theme.wellStrong
                Plate {
                    anchors.fill: parent
                    visible: cover.status !== Image.Ready
                    developOnLoad: false
                    zoom: 2.2
                }
                Image {
                    id: cover
                    anchors.fill: parent
                    source: root.m.art || ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(184, 184)
                    visible: status === Image.Ready
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 2
                Marquee {
                    Layout.fillWidth: true
                    text: root.m.title
                    font.pixelSize: Theme.fsL
                    font.weight: Font.DemiBold
                }
                Label {
                    text: root.m.artist
                    visible: text !== ""
                    color: Theme.text2
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                }
                // The output it plays on.
                Rectangle {
                    visible: root.feed.device !== ""
                    Layout.topMargin: 6
                    Layout.maximumWidth: parent.width
                    implicitWidth: chip.implicitWidth + 18
                    implicitHeight: 24
                    radius: 12
                    color: Theme.well
                    RowLayout {
                        id: chip
                        anchors.fill: parent
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        spacing: 6
                        Icon { name: root.feed.deviceBt ? "bluetooth" : "speaker"; size: 13; color: Theme.ink }
                        Label { text: root.feed.device; font.pixelSize: Theme.fsS - 1; color: Theme.text2; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                    }
                }
            }
        }

        // Scrub
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            visible: root.m.length > 0
            Cap { text: Media.clock(root.m.position); font.features: ({ "tnum": 1 }) }
            Item {
                id: track
                Layout.fillWidth: true
                implicitHeight: 16
                readonly property real progress: root.m.length > 0 ? Math.min(1, root.m.position / root.m.length) : 0
                // Keyboard: Left and Right seek 5 seconds when the player allows it.
                activeFocusOnTab: root.m.canSeek
                Keys.onPressed: event => {
                    KeyNav.key();
                    if (!root.m.canSeek || !KeyNav.plain(event) || (event.key !== Qt.Key_Left && event.key !== Qt.Key_Right)) return;
                    root.feed.seek(Math.max(0, Math.min(root.m.length, root.m.position + (event.key === Qt.Key_Right ? 5 : -5))));
                    event.accepted = true;
                }
                FocusRing { radius: 8 }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Theme.wellStrong
                    Rectangle {
                        height: parent.height
                        radius: 2
                        color: Theme.ink
                        width: track.progress * parent.width
                        Behavior on width { SpringSoft {} }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: root.m.canSeek
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: mouse => root.feed.seek(Math.max(0, Math.min(1, mouse.x / width)) * root.m.length)
                }
            }
            Cap { text: "-" + Media.clock(root.m.length - root.m.position); font.features: ({ "tnum": 1 }) }
        }

        // Transport
        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: 16
            SideButton { anchors.verticalCenter: parent.verticalCenter; kind: "ghost"; round: true; size: 38; icon: "prev"; onClicked: root.feed.previous() }
            SideButton { anchors.verticalCenter: parent.verticalCenter; kind: "ink"; round: true; size: 44; iconSize: 20; icon: root.m.playing ? "pause" : "play"; onClicked: root.feed.playPause() }
            SideButton { anchors.verticalCenter: parent.verticalCenter; kind: "ghost"; round: true; size: 38; icon: "next"; onClicked: root.feed.next() }
        }
    }

    // Nothing playing
    ColumnLayout {
        id: empty
        visible: !root.m.active
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; topMargin: 18 }
        spacing: 4
        Icon { Layout.alignment: Qt.AlignHCenter; name: "music"; size: 22; color: Theme.ink }
        Label { Layout.alignment: Qt.AlignHCenter; text: "Nothing playing"; font.weight: Font.DemiBold }
        Label {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            horizontalAlignment: Text.AlignHCenter
            color: Theme.text2
            text: root.m.resume ? "Resume “" + root.m.resume.title + "”" + (root.m.resume.artist ? " · " + root.m.resume.artist : "") : "Music you play shows here"
        }
        SideButton {
            visible: root.m.resume !== null
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 6
            kind: "ink"
            icon: "play"
            text: "Play"
            onClicked: root.feed.playPause()
        }
    }
}
