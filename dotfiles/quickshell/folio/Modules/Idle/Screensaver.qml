import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// The screensaver on one screen, in the lock's split (Widgets/SaverPage):
// the theme's art beside a page with the date, the clock and a few quiet
// lines; other screens show the art alone. It prints in over the desktop
// and lifts away on input (Lumen fades). Every minute Folio's art turns to
// the collection's next plate.
PanelWindow {
    id: win
    required property var idle

    readonly property bool up: idle.saver
    property bool isMain: true              // the page on the focused screen; art alone elsewhere
    property bool shown: false
    visible: shown
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "folio:screensaver"
    WlrLayershell.keyboardFocus: up ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }

    onUpChanged: {
        if (up) {
            const s = Shell.screenFor(Quickshell.screens);
            isMain = !s || !win.screen || s.name === win.screen.name;
            shown = true; cycle.index = 0; page.plate = Art.current; ink.printIn(Theme.tDevelop);
        }
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
            page.plate = list[(list.indexOf(Art.current) + index) % list.length];
        }
    }

    Develop {
        id: ink
        anchors.fill: parent
        progress: 0
        grain: 1.4
        onFinished: if (!win.up) win.shown = false

        SaverPage {
            id: page
            anchors.fill: parent
            main: win.isMain
            running: win.up
            caption: win.idle.fx ? win.idle.fx.caption : ""
        }
    }


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
