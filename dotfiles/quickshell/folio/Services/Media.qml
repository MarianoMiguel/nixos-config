pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// The player that matters: the one playing, else the last one that played.
Singleton {
    id: root

    readonly property var players: Mpris.players.values
    property MprisPlayer last: null
    readonly property MprisPlayer player: players.find(p => p.isPlaying) || (players.indexOf(last) >= 0 ? last : null) || players[0] || null

    readonly property bool active: player !== null && player.playbackState !== MprisPlaybackState.Stopped
    readonly property bool playing: player !== null && player.isPlaying
    readonly property string title: player ? (player.trackTitle || player.identity || "") : ""
    readonly property string artist: player ? (player.trackArtist || "") : ""
    readonly property string album: player ? (player.trackAlbum || "") : ""
    readonly property string art: player ? (player.trackArtUrl || "") : ""
    readonly property real length: player && player.lengthSupported ? player.length : 0
    property real position: 0

    // MPRIS does not push the position; read it while playing.
    Timer {
        interval: 1000; repeat: true; triggeredOnStart: true
        running: root.playing
        onTriggered: if (root.player) { root.player.positionChanged(); root.position = root.player.position; }
    }
    onPlayerChanged: { if (player) last = player; position = player ? player.position : 0; }

    function toggle() { if (player && player.canTogglePlaying) player.togglePlaying(); }
    function next() { if (player && player.canGoNext) player.next(); }
    function previous() { if (player && player.canGoPrevious) player.previous(); }
    function seek(seconds) { if (player && player.canSeek) { player.position = seconds; position = seconds; } }
    function clock(s) { s = Math.max(0, Math.floor(s)); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }
}
