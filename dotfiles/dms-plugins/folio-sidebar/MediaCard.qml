import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

Rectangle {
    id: root
    readonly property var player: MprisController.activePlayer
    implicitHeight: player ? 150 : 94
    radius: Theme.cornerRadius
    color: Theme.surfaceContainer
    border.width: 1
    border.color: Theme.outlineVariant

    Column {
        anchors.fill: parent; anchors.margins: 16
        spacing: 12
        StyledText {
            text: "NOW PLAYING"
            font.family: SettingsData.monoFontFamily
            font.pixelSize: 10; font.letterSpacing: 1.5
            color: Theme.surfaceVariantText
        }
        Row {
            width: parent.width; spacing: 12
            ClippingRectangle {
                width: 42; height: 42
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh
                DankIcon { anchors.centerIn: parent; name: "music_note"; size: 24; color: Theme.primary }
                // DMS already resolves local and remote MPRIS artwork safely.
                Image {
                    anchors.fill: parent
                    source: TrackArtService.resolvedArtUrl || root.player?.trackArtUrl || ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
            }
            Column {
                width: parent.width - 54; spacing: 4
                StyledText {
                    width: parent.width
                    text: MprisController.stableTitle || (root.player ? root.player.identity : "A little quiet")
                    color: Theme.surfaceText; font.pixelSize: 14; font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                StyledText {
                    width: parent.width
                    text: MprisController.stableArtist || (root.player ? "Ready to play" : "Your music will appear here.")
                    color: Theme.surfaceVariantText; font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.player !== null
            spacing: 20
            DankActionButton {
                iconName: "skip_previous"; buttonSize: 28
                enabled: root.player?.canGoPrevious ?? false
                Accessible.name: "Previous track"
                onClicked: root.player?.previous()
            }
            DankActionButton {
                iconName: root.player?.isPlaying ? "pause" : "play_arrow"; buttonSize: 28
                enabled: root.player?.canTogglePlaying ?? false
                Accessible.name: root.player?.isPlaying ? "Pause" : "Play"
                onClicked: root.player?.togglePlaying()
            }
            DankActionButton {
                iconName: "skip_next"; buttonSize: 28
                enabled: root.player?.canGoNext ?? false
                Accessible.name: "Next track"
                onClicked: root.player?.next()
            }
        }
    }
}
