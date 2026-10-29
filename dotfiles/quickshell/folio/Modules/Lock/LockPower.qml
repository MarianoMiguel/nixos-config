import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// Power on the lock screen's right edge. Holding the tab for 1.2 s fills it
// and offers Hibernate and Shut down; shutting down counts down on the menu
// and can be cancelled (no "are you sure?"). The harness never runs them.
Item {
    id: root
    required property var lock
    property bool menu: false
    property int countdown: -1
    property real hold: 0

    readonly property var choices: countdown > 0
        ? [{ "icon": "power", "text": "Shutting down in " + countdown, "act": "none" }, { "icon": "close", "text": "Cancel", "act": "cancel" }]
        : [{ "icon": "moon", "text": "Hibernate", "act": "hibernate" }, { "icon": "power", "text": "Shut down", "act": "shutdown" }]
    property int current: -1                // keyboard choice
    onMenuChanged: current = -1

    function close() { menu = false; countdown = -1; tick.stop(); }
    function act(a) {
        if (a === "hibernate") hibernate();
        else if (a === "shutdown") { shutDown(); current = 1; }
        else if (a === "cancel") { countdown = -1; tick.stop(); current = 1; }
    }
    // Arrows choose, Return acts, Escape closes (LockPage forwards keys).
    function key(event) {
        if (!menu) return false;
        if (event.key === Qt.Key_Escape) { close(); return true; }
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            const live = choices.map((c, i) => c.act !== "none" ? i : -1).filter(i => i >= 0);
            const at = live.indexOf(current);
            current = live[event.key === Qt.Key_Down ? Math.min(live.length - 1, at + 1) : Math.max(0, at <= 0 ? 0 : at - 1)];
            return true;
        }
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && current >= 0) { act(choices[current].act); return true; }
        return false;
    }
    function hibernate() {
        close();
        if (lock.harness) { lock.message = "Hibernate would start now."; lock.messageError = false; return; }
        Session.lockThen(["systemctl", "hibernate"]);
    }
    function shutDown() { countdown = 5; tick.restart(); }
    Timer {
        id: tick
        interval: 1000; repeat: true
        onTriggered: {
            if (--root.countdown > 0) return;
            stop();
            root.close();
            if (root.lock.harness) { root.lock.message = "Shut down would start now."; root.lock.messageError = false; return; }
            Quickshell.execDetached(["systemctl", "poweroff"]);
        }
    }

    // Clicking anywhere else closes the menu.
    MouseArea { anchors.fill: parent; enabled: root.menu; onClicked: root.close() }

    Rectangle {
        id: tabRect
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 38; height: 64
        color: Theme.ink
        topLeftRadius: Theme.rM; bottomLeftRadius: Theme.rM
        clip: true
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: parent.height * root.hold
            color: Theme.rgba(Theme.inkText, 0.3)
        }
        Icon { anchors.centerIn: parent; name: "power"; size: 20; color: Theme.inkText }
        MouseArea {
            id: tabArea
            anchors.fill: parent
            hoverEnabled: true
            onPressed: { drain.stop(); fill.from = root.hold; fill.duration = 1200 * (1 - root.hold); fill.start(); }
            onReleased: if (fill.running) { fill.stop(); drain.start(); }
            onCanceled: if (fill.running) { fill.stop(); drain.start(); }
        }
        NumberAnimation {
            id: fill
            target: root; property: "hold"; to: 1
            onFinished: { root.menu = true; drain.start(); }
        }
        NumberAnimation { id: drain; target: root; property: "hold"; to: 0; duration: Theme.tPanel; easing.type: Easing.OutCubic }
    }

    // "Hold to power off", on hover.
    Item {
        anchors.right: tabRect.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: tipText.implicitWidth + 24
        height: tipText.implicitHeight + 16
        opacity: tabArea.containsMouse && !root.menu ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.tQuick } }
        Sheet { anchors.fill: parent; radius: Theme.rS; color: Theme.sheetStrong; shadow: false }
        Cap { id: tipText; anchors.centerIn: parent; text: "Hold to power off" }
    }

    // The choices.
    Item {
        id: menuBox
        anchors.right: tabRect.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 220
        height: menuCol.implicitHeight + 12
        visible: opacity > 0
        opacity: root.menu ? 1 : 0
        scale: root.menu ? 1 : 0.96
        transformOrigin: Item.Right
        Behavior on opacity { NumberAnimation { duration: Theme.tQuick } }
        Behavior on scale { SpringPress {} }
        MouseArea { anchors.fill: parent }
        Sheet { anchors.fill: parent; radius: Theme.rM; color: Theme.sheetStrong }
        ColumnLayout {
            id: menuCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            spacing: 2
            Repeater {
                model: root.choices
                Rectangle {
                    id: choice
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: Theme.inner(Theme.rM, 6)
                    readonly property bool lit: modelData.act !== "none" && (itemArea.containsMouse || root.current === index)
                    color: lit ? Theme.ink : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10; anchors.rightMargin: 10
                        spacing: 10
                        Icon { name: choice.modelData.icon; size: 16; color: choice.lit ? Theme.inkText : Theme.text }
                        Label {
                            Layout.fillWidth: true; Layout.minimumWidth: 0
                            text: choice.modelData.text
                            color: choice.lit ? Theme.inkText : Theme.text
                        }
                    }
                    MouseArea {
                        id: itemArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.act(choice.modelData.act)
                    }
                }
            }
        }
    }
}
