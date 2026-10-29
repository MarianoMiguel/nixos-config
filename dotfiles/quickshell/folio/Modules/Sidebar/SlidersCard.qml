import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// Volume and brightness. With more than one output, a chevron beside the
// volume opens the list of outputs to choose from.
SideCard {
    id: root
    required property var feed
    property bool outputsOpen: false

    implicitHeight: col.implicitHeight + 24

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            SideSlider {
                Layout.fillWidth: true
                icon: root.feed.muted || root.feed.volume === 0 ? "mute" : "speaker"
                value: root.feed.volume
                dim: root.feed.muted
                onMoved: v => root.feed.setVolume(v)
            }
            SideButton {
                visible: root.feed.outputs.length > 1
                kind: "ghost"; round: true; size: 30; iconSize: 16
                icon: "down"
                rotation: root.outputsOpen ? 180 : 0
                Behavior on rotation { SpringPress {} }
                onClicked: root.outputsOpen = !root.outputsOpen
            }
        }

        // Outputs
        Item {
            property real h: root.outputsOpen ? outs.implicitHeight : 0
            Behavior on h { SpringPanel {} }
            Layout.fillWidth: true
            Layout.preferredHeight: h
            visible: h > 0.5
            clip: true
            opacity: Math.min(1, h / 30)
            ColumnLayout {
                id: outs
                width: parent.width
                spacing: 0
                Repeater {
                    model: root.feed.outputs
                    SideTap {
                        id: out
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: Theme.rS
                        sink: false
                        onClicked: if (!modelData.current) root.feed.useOutput(modelData)
                        Rectangle { anchors.fill: parent; radius: out.radius; color: out.hovered ? Theme.well : "transparent" }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10
                            Icon { name: "speaker"; size: 15; color: out.modelData.current ? Theme.ink : Theme.text2 }
                            Label { text: out.modelData.name; font.pixelSize: Theme.fsS; font.weight: out.modelData.current ? Font.DemiBold : Font.Normal; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                            Icon { visible: out.modelData.current; name: "check"; size: 15; color: Theme.ink }
                        }
                    }
                }
            }
        }

        SideSlider {
            visible: root.feed.hasBrightness
            Layout.fillWidth: true
            icon: "sun"
            value: root.feed.brightness
            onMoved: v => root.feed.setBrightness(Math.max(0.01, v))
        }
    }
}
