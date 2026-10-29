import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// An output or input in the Sound page's lists: choosing it makes it the
// default; a muted device shows the mute mark. Draws its own hairline (`rule`)
// because Card's dividers miss rows that come from a Repeater.
Item {
    id: root
    property string key
    property bool rule: false
    readonly property var d: Audio.dev(key)
    Layout.fillWidth: true
    implicitHeight: row.implicitHeight

    ListRow {
        id: row
        width: parent.width
        icon: root.d.icon; title: root.d.title; subtitle: root.d.subtitle
        selected: root.d.isDefault
        clickable: !root.d.isDefault
        onClicked: Audio.setDefault(root.key)
        Icon { visible: root.d.muted; name: "mute"; size: 15; color: Theme.text3 }
    }
    Rectangle { visible: root.rule; x: 14; width: parent.width - 28; height: 1; color: Theme.rule }
}
