import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// Amber pill while the microphone, camera or screen is in use. It opens
// sideways from nothing and closes back into it.
Item {
    id: root

    property bool mic: false
    property bool camera: false
    property bool screen: false
    readonly property bool shown: mic || camera || screen
    // What was in use, kept while the pill closes.
    property bool heldMic: false
    property bool heldCamera: false
    property bool heldScreen: false
    function keep() { if (shown) { heldMic = mic; heldCamera = camera; heldScreen = screen; } }
    onMicChanged: keep()
    onCameraChanged: keep()
    onScreenChanged: keep()
    Component.onCompleted: keep()

    Layout.preferredWidth: shown ? pill.width : 0
    Layout.preferredHeight: 22
    Behavior on Layout.preferredWidth { SpringPanel {} }
    clip: true
    opacity: shown ? 1 : 0
    Behavior on opacity { SpringSoft {} }
    visible: opacity > 0.01

    Rectangle {
        id: pill
        anchors.right: parent.right
        width: icons.implicitWidth + 14
        height: 22
        radius: height / 2
        color: Theme.rgba(Theme.warning, 0.18)
        Row {
            id: icons
            anchors.centerIn: parent
            spacing: 3
            Icon { visible: root.heldMic; name: "mic"; size: 13; color: Theme.warning }
            Icon { visible: root.heldCamera; name: "camera"; size: 13; color: Theme.warning }
            Icon { visible: root.heldScreen; name: "screen"; size: 13; color: Theme.warning }
        }
    }
}
