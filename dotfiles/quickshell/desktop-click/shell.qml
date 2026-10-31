// Clicks on exposed wallpaper. A left click shows the nearest empty workspace
// on that display; a right click opens Folio's desktop menu at that point
// (Modules/Desktop in dotfiles/quickshell/folio).
//
// It lives on the Wayland Bottom layer: above the wallpaper (Background), but
// below every real window and below the bar/dock (Top). Because windows and
// the dock sit on higher layers, this surface only ever receives clicks that
// land on bare wallpaper, without stealing window or dock input.
//
// Runs as its own Quickshell instance (qs -c desktop-click), independent of
// the shell, so it works under DMS as well; the right click then does nothing.

import Quickshell
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: root

    // Asks Folio for its desktop menu at x, y on that screen (its own
    // coordinates: this surface covers the whole screen). Best effort and
    // silent: under DMS no Folio answers, and nothing is said.
    function menuCommand(screen, x, y) {
        return ["sh", "-c", 'exec qs ipc -c folio call desktop menu "$1" "$2" "$3" >/dev/null 2>&1', "sh",
                screen, String(Math.round(x)), String(Math.round(y))];
    }

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
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton)
                        Quickshell.execDetached(root.menuCommand(modelData.name, mouse.x, mouse.y));
                    else
                        Quickshell.execDetached(["niri-focus-empty", modelData.name]);
                }
            }
        }
    }
}
