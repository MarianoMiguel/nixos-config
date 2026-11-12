import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// Default apps: which app opens each kind of link and file. DefaultApps reads
// the current defaults and the apps that can take each one, and sets them
// with xdg-mime (dry-run in the harness). When Home Manager owns
// mimeapps.list the defaults are shown read-only. A fixture (IPC apps
// fixture normal|stress|empty|managed) shows test data instead.
SettingsPage {
    id: page
    title: "Default apps"
    description: "Which app opens links, folders and files of each kind."
    Component.onCompleted: if (!DefaultApps.fx) DefaultApps.refresh()

    Notice {
        visible: DefaultApps.managed
        Layout.topMargin: 18
        icon: "lock"
        text: "Home Manager manages ~/.config/mimeapps.list, so these are read-only here: set them in xdg.mimeApps.defaultApplications in Nix."
    }

    Section {
        title: "Open with"
        hint: DefaultApps.managed ? "" : "Saved in ~/.config/mimeapps.list, ahead of the system defaults set in Nix."
    }
    Card {
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Repeater {
                model: DefaultApps.rows
                AppsChooser {
                    required property var modelData
                    required property int index
                    row: modelData
                    first: index === 0
                    readOnly: DefaultApps.readOnly(modelData.kind)
                    expanded: DefaultApps.open === modelData.kind.id
                    onToggled: DefaultApps.open = expanded ? "" : modelData.kind.id
                    onChosen: id => DefaultApps.choose(modelData.kind.id, id)
                    Component.onCompleted: page.mark(modelData.kind.id, this)
                }
            }
        }
    }
}
