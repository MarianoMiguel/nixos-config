import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

// One toast: an optional ink badge, the text (countdowns count down live),
// the action (Undo, Cancel) and a close. It rises from under the dock and
// prints in; leaving, it sinks back the way it came and lifts off.
Item {
    id: card
    property var toast: ({})
    // Hovering a toast stops its clock.
    HoverHandler { onHoveredChanged: if (card.toast && card.toast.id) Toasts.hold(card.toast.id, hovered) }
    property bool leaving: false
    property real targetY: 0                // where it rests
    property real startY: 0                 // where it comes from and goes back to
    property real maxWidth: 480
    readonly property real pad: 24          // room for the shadow
    readonly property Item surface: sheet
    readonly property bool printed: dev.progress > 0.4 && !leaving
    signal gone()

    readonly property string text: {
        const t = card.toast;
        if (!t.countdown) return t.text || "";
        return (t.text || "") + " in " + Toasts.remaining(t) + " s";
    }

    width: sheet.width + pad * 2
    height: sheet.height + pad * 2

    property bool ready: false
    y: ready ? (leaving ? startY : targetY) : startY
    Behavior on y { enabled: card.ready; SpringPanel {} }
    Component.onCompleted: { dev.progress = 0; dev.printIn(600); Qt.callLater(() => card.ready = true); }
    onLeavingChanged: {
        if (leaving) dev.lift(260);
        else dev.run(dev.progress, 1, Math.max(1, (1 - dev.progress) * 600));
    }

    Develop {
        id: dev
        anchors.fill: parent
        grain: 1
        onFinished: if (card.leaving && progress === 0) card.gone()

        Sheet {
            id: sheet
            x: card.pad; y: card.pad
            width: Math.min(card.maxWidth, Math.max(280, row.implicitWidth + 16))
            height: 48
            radius: Theme.rL

            RowLayout {
                id: row
                anchors.fill: parent
                anchors.margins: 8
                spacing: 12

                Rectangle {
                    visible: (card.toast.icon || "") !== ""
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: Theme.inner(Theme.rL, 8)
                    color: Theme.ink
                    Icon { anchors.centerIn: parent; name: card.toast.icon || ""; size: 17; color: Theme.inkText }
                }
                Label {
                    text: card.text
                    font.features: { "tnum": 1 }
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.leftMargin: (card.toast.icon || "") !== "" ? 0 : 8
                }
                Rectangle {
                    id: act
                    visible: (card.toast.action || "") !== ""
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: actLabel.implicitWidth + 24
                    radius: Theme.inner(Theme.rL, 8)
                    color: actArea.containsMouse ? Theme.wellStrong : Theme.well
                    border.width: 1
                    border.color: Theme.rule
                    scale: actArea.pressed ? 0.95 : 1
                    Behavior on scale { SpringPress {} }
                    Label {
                        id: actLabel
                        anchors.centerIn: parent
                        text: card.toast.action || ""
                        color: Theme.ink
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: actArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: !card.leaving
                        onClicked: Toasts.act(card.toast.id)
                    }
                }
                // A countdown only stops with Cancel: closing it would run it now.
                Rectangle {
                    visible: !card.toast.countdown
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
                        onClicked: Toasts.dismiss(card.toast.id)
                    }
                }
            }
        }
    }
}
