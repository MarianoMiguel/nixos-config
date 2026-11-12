import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// A sound card's profile (Bluetooth: high fidelity or headset; HDMI on or
// off; the jack's headphones or the speaker): the current one, and the others
// in a drawer. Shown only when there is more than one to choose from.
ColumnLayout {
    id: root
    property string cardKey
    property string panel               // output | input
    property bool allowed: true         // false hides it (the input's card when it is the output's)
    readonly property var c: Audio.card(cardKey)
    readonly property var choices: c ? c.profiles.filter(p => p.name !== "off").concat(c.profiles.filter(p => p.name === "off")) : []
    readonly property var cur: c ? (c.profiles.find(p => p.index === c.current) || null) : null
    readonly property bool open: Audio.openPanel === "profile:" + panel
    visible: allowed && !!c && c.profiles.filter(p => p.name !== "off").length >= 2
    Layout.fillWidth: true
    spacing: 0

    SettingRow {
        icon: "chip"; label: "Profile"; hint: root.cur ? root.cur.title : "Off"
        Button { text: root.open ? "Done" : "Change"; onClicked: Audio.openPanel = root.open ? "" : "profile:" + root.panel }
    }
    SoundDrawer {
        open: root.open
        Repeater {
            model: root.choices
            ListRow {
                required property var modelData
                Layout.leftMargin: 42
                title: modelData.title
                subtitle: Audio.profileHint(modelData)
                selected: !!root.c && modelData.index === root.c.current
                dim: !modelData.available
                clickable: modelData.available && !selected
                onClicked: Audio.setProfile(root.cardKey, modelData.index)
            }
        }
        Item { Layout.preferredHeight: 6 }
    }
}
