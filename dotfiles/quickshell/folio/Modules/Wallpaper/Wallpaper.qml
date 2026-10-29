import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets

// The living plate on every screen: develops when the session starts, keeps
// its dither moving, dissolves to a new plate and bleeds in a new ink or mode.
Scope {
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            color: Theme.paper
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "folio:wallpaper"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            mask: Region {}

            Plate {
                anchors.fill: parent
                breathe: Settings.get("plates.breathe")
            }
        }
    }
}
