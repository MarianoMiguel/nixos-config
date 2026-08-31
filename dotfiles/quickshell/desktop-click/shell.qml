// A thin clickable strip along the bottom of every screen that jumps to the
// always-empty trailing workspace when clicked.
//
// It lives on the Wayland Bottom layer: above the wallpaper (Background), but
// below every real window and below the DMS bar/dock (Top). Because windows and
// the dock sit on higher layers, this surface only ever receives clicks that
// land on bare wallpaper along the bottom edge, beside the dock — exactly the
// gesture we want, with no risk of stealing window or dock input.
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

            // Full-width band pinned to the bottom edge. Anchoring only three
            // sides plus a fixed height gives the strip; exclusiveZone 0 keeps
            // it from reserving space and shifting windows.
            anchors {
                bottom: true
                left: true
                right: true
            }
            implicitHeight: 160
            exclusiveZone: 0
            color: "transparent"

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: Quickshell.execDetached(["niri-focus-empty"])
            }
        }
    }
}
