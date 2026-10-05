// Clicking exposed wallpaper shows the nearest empty workspace on that display.
//
// It lives on the Wayland Bottom layer: above the wallpaper (Background), but
// below every real window and below the DMS bar/dock (Top). Because windows and
// the dock sit on higher layers, this surface only ever receives clicks that
// land on bare wallpaper, without stealing window or dock input.
//
// Runs as its own Quickshell instance (qs -c desktop-click), independent of DMS.

import Quickshell
import Quickshell.Wayland
import QtQuick

ShellRoot {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData

            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "desktop-click-empty"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Include wallpaper beside the bar/dock's reserved strips too.
            // Normal exclusion would shrink this to the window work area.
            exclusionMode: ExclusionMode.Ignore
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: "transparent"

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: Quickshell.execDetached(["niri-focus-empty", modelData.name])
            }
        }
    }
}
