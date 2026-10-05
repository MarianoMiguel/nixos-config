import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Notifications.Center

Item {
    id: root
    required property var sidebar
    property bool expanded: false
    readonly property bool shouldBeVisible: sidebar.shouldBeVisible && expanded
    readonly property bool hostOwnsHeight: true
    readonly property bool animateCardExpansion: true
    readonly property var screen: sidebar.screen
    readonly property real maxContentHeight: height
    readonly property alias transientSurfaceTracker: tracker
    implicitHeight: Math.min(460, Math.max(300, (screen?.height || 900) * 0.42))
    function close() { sidebar.close(); }
    function requestSettings() {
        sidebar.close();
        Quickshell.execDetached(["dms", "ipc", "call", "settings", "open"]);
    }
    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            NotificationService.onOverlayOpen();
            keyboard.reset();
            keyboard.rebuildFlatNavigation();
        }
    }
    TransientSurfaceTracker { id: tracker }
    NotificationKeyboardController {
        id: keyboard
        listView: content.notificationList
        isOpen: root.shouldBeVisible
        onClose: () => root.close()
    }
    NotificationCenterContent {
        id: content
        anchors.fill: parent
        host: root
        externalKeyboardController: keyboard
        Component.onCompleted: {
            root.sidebar.reportPanel("notifications", true);
            notificationList.keyboardController = keyboard;
            notificationHeader.keyboardController = keyboard;
        }
        Keys.onPressed: event => handleKey(event)
    }
}
