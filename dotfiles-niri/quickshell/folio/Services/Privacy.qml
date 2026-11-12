pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Who is using the microphone, the camera or the screen, from PipeWire.
Singleton {
    id: root

    function cls(n) { return (n.properties && n.properties["media.class"]) || ""; }
    function app(n) { return (n.properties && (n.properties["application.name"] || n.properties["node.name"])) || n.name || ""; }

    readonly property var micApps: Pipewire.nodes.values.filter(n => n.isStream && cls(n) === "Stream/Input/Audio").map(app)
    readonly property var cameraApps: Pipewire.nodes.values.filter(n => n.isStream && cls(n) === "Stream/Input/Video").map(app)
    readonly property bool screen: Pipewire.nodes.values.some(n => cls(n) === "Video/Source" && /niri|xdg-desktop-portal|screen/i.test(app(n)))
    readonly property bool mic: micApps.length > 0
    readonly property bool camera: cameraApps.length > 0
    readonly property bool any: mic || camera || screen
}
