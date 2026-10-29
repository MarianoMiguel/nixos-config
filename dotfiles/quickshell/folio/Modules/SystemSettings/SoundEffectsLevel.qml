import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// The effects volume on the Sound page ("sounds.volume", through Audio's
// preferences so fixtures and the harness keep their own): the play button
// sounds a notification at this level; letting go of the slider saves the
// level and confirms it with a short tap. Lines up with the volume rows.
SoundRow {
    id: root
    icon: "bell"; label: "Effects volume"
    hint: "Notifications too"

    property real pending: -1               // the level being dragged, saved shortly after it stops
    readonly property real value: pending >= 0 ? pending : Sounds.level(Audio.pref("sounds.volume"))

    Button { Layout.preferredWidth: 41; icon: "play"; onClicked: Sounds.audition("notification") }
    Slider {
        Layout.fillWidth: true; Layout.minimumWidth: 80
        value: root.value
        onMoved: v => { root.pending = v; commit.restart(); }
    }
    Label {
        Layout.preferredWidth: 42
        horizontalAlignment: Text.AlignRight
        text: Math.round(root.value * 100) + "%"
        font.family: Theme.mono; font.pixelSize: Theme.fsS
        color: root.value > 0 ? Theme.text2 : Theme.text3
    }
    Timer {
        id: commit
        interval: 300
        onTriggered: { Sounds.setVolume(root.pending); root.pending = -1; Sounds.audition("pop"); }
    }
}
