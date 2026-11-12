import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// The drive toast: an ink badge, what happened, its actions (Open, Eject)
// and a close, or a turning arrow while something runs. It looks and moves
// like Folio's toasts (Modules/Toasts/ToastCard): rises from under the dock
// or from behind the toast below, prints in, and leaving sinks back the way
// it came and lifts off. Its width glides when the words change.
Item {
    id: card
    property bool leaving: true
    property string text
    property string detail                  // after the text, never elided ("· 32 GB")
    property string icon: "usb"
    property var actions: []                // labels, left to right
    property bool working: false
    property real targetY: 0
    property real startY: 0
    property real maxWidth: 500
    readonly property real pad: 24
    readonly property Item surface: sheet
    readonly property bool printed: dev.progress > 0.4 && !leaving
    readonly property bool hovered: hover.hovered
    property bool gone: true                // fully lifted off
    signal acted(int index)
    signal closed()

    width: sheet.width + pad * 2
    height: sheet.height + pad * 2

    property bool ready: false
    y: ready ? (leaving ? startY : targetY) : startY
    Behavior on y { enabled: card.ready; SpringPanel {} }
    onLeavingChanged: {
        if (!leaving) {
            if (gone) {
                gone = false;
                ready = false;
                dev.progress = 0;
                dev.printIn(600);
                Qt.callLater(() => card.ready = true);
            } else dev.run(dev.progress, 1, Math.max(1, (1 - dev.progress) * 600));
        } else dev.lift(260);
    }

    HoverHandler { id: hover }

    Develop {
        id: dev
        anchors.fill: parent
        grain: 1
        progress: 0
        onFinished: if (card.leaving && progress === 0) { card.gone = true; card.ready = false; }

        Sheet {
            id: sheet
            x: card.pad; y: card.pad
            width: Math.min(card.maxWidth, Math.max(300, row.implicitWidth + 16))
            height: 48
            radius: Theme.rL
            Behavior on width { enabled: card.ready; SpringPanel {} }

            RowLayout {
                id: row
                anchors.fill: parent
                anchors.margins: 8
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: Theme.inner(Theme.rL, 8)
                    color: Theme.ink
                    Icon { anchors.centerIn: parent; name: card.icon; size: 17; color: Theme.inkText }
                }
                // The text elides; the detail after it stays whole.
                Item {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitWidth: main.implicitWidth + more.implicitWidth
                    implicitHeight: main.implicitHeight
                    Label {
                        id: main
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width - more.implicitWidth)
                        text: card.text
                    }
                    Label {
                        id: more
                        visible: card.detail !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        x: main.width
                        text: card.detail
                        color: Theme.text2
                        font.features: { "tnum": 1 }
                    }
                }
                Repeater {
                    model: card.working ? [] : card.actions
                    Rectangle {
                        required property string modelData
                        required property int index
                        Layout.preferredHeight: 32
                        Layout.preferredWidth: actLabel.implicitWidth + 24
                        radius: Theme.inner(Theme.rL, 8)
                        color: actArea.containsMouse ? Theme.wellStrong : Theme.well
                        border.width: 1
                        border.color: Theme.rule
                        scale: actArea.pressed ? 0.95 : 1
                        Behavior on scale { SpringPress {} }
                        Behavior on color { ColorAnimation { duration: Theme.tQuick } }
                        Label {
                            id: actLabel
                            anchors.centerIn: parent
                            text: modelData
                            color: Theme.ink
                            font.weight: Font.DemiBold
                        }
                        MouseArea {
                            id: actArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !card.leaving
                            onClicked: card.acted(index)
                        }
                    }
                }
                // Something runs (ejecting, mounting): a turning arrow.
                Item {
                    visible: card.working
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    Icon {
                        anchors.centerIn: parent
                        name: "reload"; size: 16; color: Theme.ink
                        RotationAnimation on rotation { running: card.working; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                    }
                }
                Rectangle {
                    visible: !card.working
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: 16
                    color: closeArea.containsMouse ? Theme.well : "transparent"
                    scale: closeArea.pressed ? 0.92 : 1
                    Behavior on scale { SpringPress {} }
                    Icon { anchors.centerIn: parent; name: "close"; size: 14; color: Theme.text2 }
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: !card.leaving
                        onClicked: card.closed()
                    }
                }
            }
        }
    }
}
