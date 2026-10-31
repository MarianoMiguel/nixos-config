import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// The screensaver on one screen: the plate printed over everything,
// breathing at full intensity, with the clock drifting slowly on a frosted
// sheet. It prints in over the desktop and lifts away dot by dot on input.
// Every minute it dissolves to the collection's next plate.
PanelWindow {
    id: win
    required property var idle

    readonly property bool up: idle.saver
    property bool shown: false
    visible: shown
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "folio:screensaver"
    WlrLayershell.keyboardFocus: up ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }

    onUpChanged: {
        if (up) { shown = true; cycle.index = 0; plate.plate = Art.current; ink.printIn(Theme.tDevelop); }
        else if (shown) ink.lift(420);
    }

    // The plates of the current collection, in order from the current one.
    readonly property var collection: {
        const c = Art.collections.find(x => x.art.some(a => a.id === Art.current));
        return c ? c.art.map(a => a.id) : [Art.current];
    }
    Timer {
        id: cycle
        property int index: 0
        interval: 60000; repeat: true
        running: win.up && win.collection.length > 1
        onTriggered: {
            const list = win.collection;
            index = (index + 1) % list.length;
            plate.plate = list[(list.indexOf(Art.current) + index) % list.length];
        }
    }

    Develop {
        id: ink
        anchors.fill: parent
        progress: 0
        grain: 1.4
        onFinished: if (!win.up) win.shown = false

        Plate {
            id: plate
            anchors.fill: parent
            plate: Art.current
            breathe: 1
            lift: 0.06
            developOnLoad: false
        }

        // The clock drifts on a slow loop through four resting places.
        Item {
            id: drift
            property real fx: 0.08
            property real fy: 0.18
            x: (win.width - width) * fx
            y: (win.height - height) * fy
            width: clockText.implicitWidth + 52
            height: clockBox.height + 40
            Frost { anchors.fill: parent; source: plate; radius: Theme.rXl }
            Sheet { anchors.fill: parent; radius: Theme.rXl }
            Item {
                id: clockBox
                x: 26; y: 20
                readonly property real size: Math.max(96, Math.min(168, win.width * 0.085))
                width: clockText.implicitWidth
                height: size * 0.8
                PrintText {
                    id: clockText
                    y: (clockBox.height - implicitHeight) / 2
                    text: Qt.formatTime(clock.date, "HH:mm")
                    color: Theme.ink
                    font.family: Theme.hero; font.weight: Theme.heroWeight
                    font.pixelSize: clockBox.size
                    font.features: { "tnum": 1 }
                }
            }
            SequentialAnimation {
                running: win.up
                loops: Animation.Infinite
                ParallelAnimation {
                    NumberAnimation { target: drift; property: "fx"; to: 0.34; duration: 20000; easing.type: Easing.InOutSine }
                    NumberAnimation { target: drift; property: "fy"; to: 0.78; duration: 20000; easing.type: Easing.InOutSine }
                }
                ParallelAnimation {
                    NumberAnimation { target: drift; property: "fx"; to: 0.86; duration: 20000; easing.type: Easing.InOutSine }
                    NumberAnimation { target: drift; property: "fy"; to: 0.3; duration: 20000; easing.type: Easing.InOutSine }
                }
                ParallelAnimation {
                    NumberAnimation { target: drift; property: "fx"; to: 0.6; duration: 20000; easing.type: Easing.InOutSine }
                    NumberAnimation { target: drift; property: "fy"; to: 0.88; duration: 20000; easing.type: Easing.InOutSine }
                }
                ParallelAnimation {
                    NumberAnimation { target: drift; property: "fx"; to: 0.08; duration: 20000; easing.type: Easing.InOutSine }
                    NumberAnimation { target: drift; property: "fy"; to: 0.18; duration: 20000; easing.type: Easing.InOutSine }
                }
            }
        }

        // What is printing, bottom right.
        Item {
            readonly property string text: {
                if (win.idle.fx) return win.idle.fx.caption;
                const p = Art.plate(plate.plate);
                const c = Art.collections.find(x => x.art.some(a => a.id === plate.plate));
                return p ? (c ? c.name + " · " : "") + p.title : "";
            }
            visible: text !== ""
            anchors { right: parent.right; bottom: parent.bottom; rightMargin: 20; bottomMargin: 18 }
            width: Math.min(caption.implicitWidth + 22, win.width * 0.4)
            height: caption.implicitHeight + 14
            Frost { anchors.fill: parent; source: plate; radius: Theme.rS }
            Sheet { anchors.fill: parent; radius: Theme.rS; color: Theme.sheetStrong }
            Cap {
                id: caption
                anchors.fill: parent
                anchors.leftMargin: 11; anchors.rightMargin: 11
                verticalAlignment: Text.AlignVCenter
                color: Theme.text2
                text: parent.text
            }
        }
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // Input on the saver itself lifts it and goes no further.
    MouseArea {
        anchors.fill: parent
        enabled: win.up
        acceptedButtons: Qt.AllButtons
        onPressed: win.idle.dismiss()
        onWheel: win.idle.dismiss()
    }
    Item {
        focus: true
        Keys.onPressed: event => { event.accepted = true; win.idle.dismiss(); }
    }
}
