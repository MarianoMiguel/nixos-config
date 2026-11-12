//@ pragma Env QSG_RENDER_LOOP=threaded
//@ pragma Env QT_WAYLAND_DISABLE_WINDOWDECORATION=1
//@ pragma UseQApplication
//@ pragma AppId folio

import QtQuick
import Quickshell
// Quickshell registers qs.* folders by following imports from this file, and
// modules load by URL, so every shared folder is imported here.
import qs.Common
import qs.Services
import qs.Widgets

// Folio: the desktop shell. Each module loads on its own, so a broken module
// costs only itself. FOLIO_MODULES ("Wallpaper,Bar") limits what loads; the
// test harness (scripts/folio-harness) uses it.
ShellRoot {
    id: shell

    // The installed shell never hot-reloads: a reload while locked would drop
    // the session lock. Restart folio-shell.service after a rebuild instead.
    // The harness (and FOLIO_DEV=1) keep live reload for development.
    Component.onCompleted: Quickshell.watchFiles = !!(Quickshell.env("FOLIO_HARNESS") || Quickshell.env("FOLIO_DEV"))

    readonly property var only: (Quickshell.env("FOLIO_MODULES") || "").split(",").filter(s => s.length > 0)

    // Modules/<Name>/<Name>.qml, in load order.
    readonly property var modules: [
        "Wallpaper", "Bar", "Island", "Dock", "Sidebar", "Toasts", "Screenshot", "Removable",
        "Launcher", "Lock", "Idle", "Polkit", "SystemSettings", "Displays", "PowerAlerts", "Desktop"
    ]

    // Literal paths, so Quickshell's scanner reads every module folder (it
    // follows Qt.resolvedUrl strings) and a module's files are types to each other.
    readonly property var sources: ({
        "Wallpaper": Qt.resolvedUrl("Modules/Wallpaper/Wallpaper.qml"),
        "Bar": Qt.resolvedUrl("Modules/Bar/Bar.qml"),
        "Island": Qt.resolvedUrl("Modules/Island/Island.qml"),
        "Dock": Qt.resolvedUrl("Modules/Dock/Dock.qml"),
        "Sidebar": Qt.resolvedUrl("Modules/Sidebar/Sidebar.qml"),
        "Toasts": Qt.resolvedUrl("Modules/Toasts/Toasts.qml"),
        "Screenshot": Qt.resolvedUrl("Modules/Screenshot/Screenshot.qml"),
        "Removable": Qt.resolvedUrl("Modules/Removable/Removable.qml"),
        "Launcher": Qt.resolvedUrl("Modules/Launcher/Launcher.qml"),
        "Lock": Qt.resolvedUrl("Modules/Lock/Lock.qml"),
        "Idle": Qt.resolvedUrl("Modules/Idle/Idle.qml"),
        "Polkit": Qt.resolvedUrl("Modules/Polkit/Polkit.qml"),
        "SystemSettings": Qt.resolvedUrl("Modules/SystemSettings/SystemSettings.qml"),
        "Displays": Qt.resolvedUrl("Modules/Displays/Displays.qml"),
        "PowerAlerts": Qt.resolvedUrl("Modules/PowerAlerts/PowerAlerts.qml"),
        "Desktop": Qt.resolvedUrl("Modules/Desktop/Desktop.qml")
    })

    Instantiator {
        model: shell.only.length > 0 ? shell.only : shell.modules
        delegate: LazyLoader {
            required property string modelData
            active: true
            source: shell.sources[modelData] || Qt.resolvedUrl("Modules/" + modelData + "/" + modelData + ".qml")
        }
    }
}
