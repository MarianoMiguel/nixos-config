import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Widgets

// Power on the screen's right edge, as on the lock screen: hold the tab
// (pointer) or Tab to it and press Enter (keyboard) for Restart and Shut
// down. Either counts down on the menu and can be cancelled; no "are you
// sure?". The state lives in Greeter, so several screens show one countdown.
Item {
    id: root
    required property var greeter
    readonly property var g: greeter
    property real hold: 0
    readonly property bool focused: g.focusPart === "power"

    readonly property var choices: g.powerCountdown > 0
        ? [{ "icon": g.powerAction === "reboot" ? "reload" : "power", "text": (g.powerAction === "reboot" ? "Restarting in " : "Shutting down in ") + g.powerCountdown, "act": "none" }, { "icon": "close", "text": "Cancel", "act": "cancel" }]
        : [{ "icon": "reload", "text": "Restart", "act": "reboot" }, { "icon": "power", "text": "Shut down", "act": "poweroff" }]

    // Arrows choose, Return acts, Escape closes (GreeterPage forwards keys).
    function key(event) {
        if (!g.powerMenu) return false;
        const k = event.key;
        if (k === Qt.Key_Escape) { g.closePower(); return true; }
        if (k === Qt.Key_Up || k === Qt.Key_Down) {
            const live = choices.map((c, i) => c.act !== "none" ? i : -1).filter(i => i >= 0);
            const at = live.indexOf(g.powerCurrent);
            g.powerCurrent = live[k === Qt.Key_Down ? Math.min(live.length - 1, at + 1) : Math.max(0, at <= 0 ? 0 : at - 1)];
            return true;
        }
        if ((k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) && g.powerCurrent >= 0) { g.powerAct(choices[g.powerCurrent].act); return true; }
        return k !== Qt.Key_Tab && k !== Qt.Key_Backtab;
    }

    // Clicking anywhere else closes the menu.
    MouseArea { anchors.fill: parent; enabled: g.powerMenu; onClicked: g.closePower() }

    Rectangle {
        id: tabRect
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 44; height: 72
        color: Theme.ink
        topLeftRadius: Theme.rM; bottomLeftRadius: Theme.rM
        clip: true
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: parent.height * root.hold
            color: Theme.rgba(Theme.inkText, 0.3)
        }
        Icon { anchors.centerIn: parent; name: "power"; size: 22; color: Theme.inkText }
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
            onFinished: { root.g.focusPart = "power"; root.g.openPower(); drain.start(); }
        }
        NumberAnimation { id: drain; target: root; property: "hold"; to: 0; duration: Theme.tPanel; easing.type: Easing.OutCubic }
    }
    // The keyboard's ring around the tab.
    Rectangle {
        anchors.fill: tabRect
        anchors.margins: -5
        anchors.rightMargin: -10
        radius: Theme.rM + 5
        color: "transparent"
        border.width: 2
        border.color: Theme.ink
        opacity: root.focused && !root.g.powerMenu ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.tQuick } }
    }

    // "Hold to power off", on hover; "Enter for power" with the keyboard's ring.
    Item {
        anchors.right: tabRect.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: tipText.implicitWidth + 28
        height: tipText.implicitHeight + 18
        opacity: (tabArea.containsMouse || root.focused) && !root.g.powerMenu ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.tQuick } }
        Sheet { anchors.fill: parent; radius: Theme.rS; color: Theme.sheetStrong; shadow: false }
        Label {
            id: tipText
            anchors.centerIn: parent
            text: root.focused ? "Enter: restart or shut down" : "Hold to restart or shut down"
            color: Theme.text2
            font.pixelSize: 15
        }
    }

    // The choices.
    Item {
        id: menuBox
        anchors.right: tabRect.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 260
        height: menuCol.implicitHeight + 16
        visible: opacity > 0
        opacity: root.g.powerMenu ? 1 : 0
        scale: root.g.powerMenu ? 1 : 0.96
        transformOrigin: Item.Right
        Behavior on opacity { NumberAnimation { duration: Theme.tQuick } }
        Behavior on scale { SpringPress {} }
        MouseArea { anchors.fill: parent }
        Sheet { anchors.fill: parent; radius: Theme.rM; color: Theme.sheetStrong }
        ColumnLayout {
            id: menuCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 3
            Repeater {
                model: root.choices
                Rectangle {
                    id: choice
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: Theme.inner(Theme.rM, 8)
                    readonly property bool lit: modelData.act !== "none" && (itemArea.containsMouse || root.g.powerCurrent === index)
                    color: lit ? Theme.ink : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14; anchors.rightMargin: 14
                        spacing: 12
                        Icon { name: choice.modelData.icon; size: 18; color: choice.lit ? Theme.inkText : Theme.text }
                        Label {
                            Layout.fillWidth: true; Layout.minimumWidth: 0
                            text: choice.modelData.text
                            color: choice.lit ? Theme.inkText : Theme.text
                            font.pixelSize: 16
                            font.weight: choice.modelData.act === "none" ? Font.DemiBold : Font.Normal
                            font.features: ({ "tnum": 1 })
                        }
                    }
                    MouseArea {
                        id: itemArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.g.powerAct(choice.modelData.act)
                    }
                }
            }
        }
    }
}
