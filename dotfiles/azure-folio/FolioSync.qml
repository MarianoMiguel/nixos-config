import QtQuick
import Quickshell
import qs.Common
import qs.Services

// Keep the stock DMS light/dark toggle synchronized with the shared palette,
// desktop wallpaper and greeter, without polling or replacing DMS services.
QtObject {
    id: sync
    property bool armed: false
    property Timer startup: Timer {
        interval: 1800; running: true
        onTriggered: { sync.armed = true; Quickshell.execDetached(["/run/current-system/sw/bin/azure-folio", "restore"]); }
    }
    property Timer debounce: Timer {
        interval: 350
        onTriggered: Quickshell.execDetached(["/run/current-system/sw/bin/azure-folio", "set", "--mode", Theme.isLightMode ? "light" : "dark"])
    }
    property Connections modeConnection: Connections {
        target: Theme
        function onIsLightModeChanged() { if (sync.armed) sync.debounce.restart(); }
    }
}
