import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// Every interface sound with a button that plays it (Sounds.audition, at the
// effects volume, whatever the switches say), so each can be heard before it
// is turned on. The button inks in while its sound plays.
Item {
    id: root
    Layout.fillWidth: true
    implicitHeight: grid.implicitHeight + 28

    property string playing: ""
    function play(name) {
        Sounds.audition(name);
        playing = name;
        playingEnds.restart();
    }
    Timer { id: playingEnds; interval: 650; onTriggered: root.playing = "" }

    GridLayout {
        id: grid
        x: 14; y: 14
        width: parent.width - 28
        columnSpacing: 8; rowSpacing: 8
        columns: Math.max(1, Math.floor((width + columnSpacing) / (168 + columnSpacing)))
        Repeater {
            model: Sounds.catalogue
            Button {
                required property var modelData
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: (grid.width - (grid.columns - 1) * grid.columnSpacing) / grid.columns
                icon: root.playing === modelData.name ? "speaker" : "play"
                text: modelData.label
                primary: root.playing === modelData.name
                onClicked: root.play(modelData.name)
            }
        }
    }
}
