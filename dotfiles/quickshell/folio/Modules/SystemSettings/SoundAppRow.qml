import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// An app playing sound: its icon (as shipped), name and what it plays, where
// it plays (opens the outputs to move it), and its own volume and mute.
Item {
    id: root
    property string key
    property bool rule: false           // its own hairline (Card's miss repeated rows)
    readonly property var s: Audio.stream(key)
    readonly property var target: Audio.dev(s.target)
    readonly property bool open: Audio.openPanel === "move:" + key
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 16

    // The theme icon by the stream's own name, else its desktop entry's.
    // Reads the entry list so the binding updates once entries have loaded.
    function iconSource(hint, app) {
        if (DesktopEntries.applications.values.length < 0) return "";
        for (const name of [hint, app]) {
            if (!name) continue;
            if (name.indexOf("/") === 0) return "file://" + name;
            const direct = Quickshell.iconPath(name, true) || Quickshell.iconPath(name.toLowerCase(), true);
            if (direct) return direct;
            const e = DesktopEntries.heuristicLookup(name);
            if (e && e.icon) return e.icon.indexOf("/") === 0 ? "file://" + e.icon : Quickshell.iconPath(e.icon, true);
        }
        return "";
    }

    Rectangle { visible: root.rule; x: 14; width: parent.width - 28; height: 1; color: Theme.rule }
    ColumnLayout {
        id: col
        x: 14; y: 8; width: parent.width - 28
        spacing: 6
        RowLayout {
            Layout.fillWidth: true; spacing: 12
            Item {
                Layout.preferredWidth: 30; Layout.preferredHeight: 30
                Image {
                    id: img
                    anchors.fill: parent
                    source: root.iconSource(root.s.icon, root.s.app)
                    sourceSize: Qt.size(60, 60)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true; smooth: true; mipmap: true
                    visible: status === Image.Ready
                }
                Rectangle {
                    anchors.fill: parent; radius: 9
                    visible: img.status !== Image.Ready
                    color: Theme.rgba(Theme.ink, 0.12)
                    Icon { anchors.centerIn: parent; name: "music"; size: 16; color: Theme.ink }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 1
                Label { text: root.s.app; font.weight: Font.Medium; Layout.fillWidth: true }
                Label { visible: root.s.title !== ""; text: root.s.title; color: Theme.text2; font.pixelSize: Theme.fsS; Layout.fillWidth: true }
            }
            // Where it plays: a pill that opens the outputs.
            Rectangle {
                Layout.preferredWidth: Math.min(220, pick.implicitWidth + 18)
                Layout.preferredHeight: 30
                radius: Theme.rS
                color: pickArea.containsMouse || root.open ? Theme.wellStrong : Theme.well
                border.color: Theme.rule
                Behavior on color { ColorAnimation { duration: Theme.tQuick } }
                RowLayout {
                    id: pick
                    anchors.fill: parent; anchors.leftMargin: 9; anchors.rightMargin: 9; spacing: 6
                    Icon { name: root.target.ok ? root.target.icon : "speaker"; size: 14; color: Theme.ink }
                    Label { text: root.target.ok ? root.target.title : "Not playing"; font.pixelSize: Theme.fsS; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                    Icon { name: "down"; size: 13; color: Theme.text2; rotation: root.open ? 180 : 0; Behavior on rotation { SpringPress {} } }
                }
                MouseArea {
                    id: pickArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Audio.openPanel = root.open ? "" : "move:" + root.key
                }
            }
        }
        // Same columns as SoundRow, so app sliders line up with the device ones.
        RowLayout {
            Layout.fillWidth: true; Layout.leftMargin: 30 + 12 + 150 + 12; spacing: 12
            Button { Layout.preferredWidth: 41; icon: root.s.muted ? "mute" : "speaker"; onClicked: Audio.setStreamMuted(root.key, !root.s.muted) }
            Slider {
                Layout.fillWidth: true; Layout.minimumWidth: 80
                value: root.s.volume; to: Audio.maxVolume; dim: root.s.muted
                onMoved: v => Audio.setStreamVolume(root.key, v)
            }
            Label {
                Layout.preferredWidth: 42
                horizontalAlignment: Text.AlignRight
                text: Math.round(root.s.volume * 100) + "%"
                font.family: Theme.mono; font.pixelSize: Theme.fsS
                color: root.s.muted ? Theme.text3 : root.s.volume > 1.005 ? Theme.warning : Theme.text2
            }
        }
        SoundDrawer {
            open: root.open
            Layout.leftMargin: 30
            Cap { text: "Play on"; Layout.leftMargin: 14; Layout.topMargin: 4; Layout.bottomMargin: 2; Layout.fillWidth: true }
            Repeater {
                model: ScriptModel { values: Audio.outputKeys }
                ListRow {
                    required property var modelData
                    readonly property var d: Audio.dev(modelData)
                    icon: d.icon; title: d.title; subtitle: d.subtitle
                    selected: modelData === root.s.target
                    clickable: !selected
                    onClicked: { Audio.moveStream(root.key, modelData); Audio.openPanel = ""; }
                }
            }
        }
    }
}
