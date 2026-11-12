import QtQuick
import qs.Common
import qs.Services

// Workspace dots: the active one is a 20 px ink pill, the rest 6 px dots;
// widths move on a spring. More than six compress. Click focuses, the wheel
// steps through them.
Item {
    id: root

    property var model: []
    signal picked(var ws)

    readonly property bool many: model.length > 6
    readonly property real dot: many ? 4 : 6
    readonly property real pill: many ? 14 : 20
    readonly property real gap: many ? 3 : 5

    implicitWidth: row.width + 20
    implicitHeight: 26

    Row {
        id: row
        anchors.centerIn: parent
        // Delegates are kept by index so a change of the active one animates.
        Repeater {
            model: root.model.length
            Item {
                id: slot
                required property int index
                readonly property var ws: root.model[index] || ({})
                readonly property bool on: !!ws.is_active
                width: (on ? root.pill : root.dot) + (index < root.model.length - 1 ? root.gap : 0)
                height: 26
                Behavior on width { SpringPanel {} }

                Rectangle {
                    width: slot.width - (slot.index < root.model.length - 1 ? root.gap : 0)
                    height: root.dot
                    anchors.verticalCenter: parent.verticalCenter
                    radius: height / 2
                    color: slot.on ? Theme.ink : Theme.text3
                    opacity: slot.on ? 1 : (area.containsMouse ? 0.8 : 0.5)
                    Behavior on color { ColorAnimation { duration: Theme.tQuick } }
                    Behavior on opacity { NumberAnimation { duration: Theme.tQuick } }
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(slot.ws)
                }
            }
        }
    }

    // niri's workspaces run top to bottom: wheel down is the next one.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        property real acc: 0
        onWheel: event => {
            acc += event.angleDelta.y;
            if (Math.abs(acc) < 120) return;
            Niri.action([acc < 0 ? "focus-workspace-down" : "focus-workspace-up"]);
            acc = 0;
        }
    }
}
