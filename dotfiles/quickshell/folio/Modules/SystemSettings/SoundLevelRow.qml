import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// A volume row on the Sound page: the mute button, the slider and the level
// in percent. `to` is 1.5 with over-amplification; above 100% the number
// turns to the warning colour.
SoundRow {
    id: root
    property real value: 0
    property bool muted: false
    property real to: 1
    signal moved(real v)
    signal muteToggled()

    Button { Layout.preferredWidth: 41; icon: root.muted ? "mute" : root.icon; onClicked: root.muteToggled() }
    Slider {
        Layout.fillWidth: true; Layout.minimumWidth: 80
        value: root.value; to: root.to; dim: root.muted
        onMoved: v => root.moved(v)
    }
    Label {
        Layout.preferredWidth: 42
        horizontalAlignment: Text.AlignRight
        text: Math.round(root.value * 100) + "%"
        font.family: Theme.mono; font.pixelSize: Theme.fsS
        color: root.muted ? Theme.text3 : root.value > 1.005 ? Theme.warning : Theme.text2
    }
}
