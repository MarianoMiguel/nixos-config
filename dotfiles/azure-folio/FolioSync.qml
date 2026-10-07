import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
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
    // Niri reports mode, scale, transform and hotplug changes together. Render
    // once the output configuration settles; the CLI serializes this with art
    // selection so an old docking event cannot restore yesterday's wallpaper.
    property Timer displays: Timer {
        interval: 650
        onTriggered: Quickshell.execDetached(["/run/current-system/sw/bin/azure-folio", "refresh-wallpapers"])
    }
    property Connections outputConnection: Connections {
        target: NiriService
        function onOutputsChanged() { if (sync.armed) sync.displays.restart(); }
    }
    // Older Niri versions don't emit OutputsChanged for every runtime change.
    // Observe Wayland's screen list/geometry as well, then query fresh physical
    // modes in the CLI instead of relying on DMS's cached output metadata.
    property Connections screenConnection: Connections {
        target: Quickshell
        function onScreensChanged() { if (sync.armed) sync.displays.restart(); }
    }
    property Instantiator screenGeometry: Instantiator {
        model: Quickshell.screens
        delegate: Connections {
            required property ShellScreen modelData
            target: modelData
            function onGeometryChanged() { if (sync.armed) sync.displays.restart(); }
            function onPhysicalPixelDensityChanged() { if (sync.armed) sync.displays.restart(); }
        }
    }
    property IpcHandler wallpaperIpc: IpcHandler {
        target: "folioWallpaper"
        function get(): string { return SessionData.wallpaperPath || ""; }
        function apply(defaultPath: string, encoded: string): string {
            if (!defaultPath.startsWith("/")) return "ERROR: Absolute default path required";
            let wallpapers;
            try { wallpapers = JSON.parse(encoded); }
            catch (e) { return "ERROR: Invalid wallpaper map"; }
            if (!wallpapers || Array.isArray(wallpapers) || typeof wallpapers !== "object")
                return "ERROR: Wallpaper map required";
            for (const [name, path] of Object.entries(wallpapers))
                if (!name || typeof path !== "string" || !path.startsWith("/"))
                    return "ERROR: Absolute per-display paths required";
            const changed = SessionData.wallpaperPath !== defaultPath;
            if (!changed && SessionData.perMonitorWallpaper && JSON.stringify(SessionData.monitorWallpapers) === JSON.stringify(wallpapers))
                return "SUCCESS: Display wallpapers already current";
            // One synchronous update: the same art/palette on every connector,
            // each using its native-size crop. The default covers new displays
            // until their first render finishes. Folio owns mode switching.
            SessionData.perModeWallpaper = false;
            SessionData.wallpaperPath = defaultPath;
            SessionData.monitorWallpapers = wallpapers;
            SessionData.perMonitorWallpaper = Object.keys(wallpapers).length > 0;
            SessionData.wallpaperCyclingFolderPath = "";
            SessionData.saveSettings();
            if (changed) Theme.generateSystemThemesFromCurrentTheme();
            return "SUCCESS: Display wallpapers updated";
        }
    }
}
