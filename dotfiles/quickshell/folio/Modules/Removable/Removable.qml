import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services

// What the desktop does when a removable drive comes and goes
// (Services/Drives, which also mounts it unless Settings say not to): a
// toast above the dock, "SanDisk Ultra · 32 GB", with Open and Eject.
// Ejecting turns it into "Safe to remove", wherever the eject started; a
// drive pulled out while mounted gets a warning; an eject that fails (files
// still open) says so and offers Try again.
//
// Folio's toasts carry one action, so this card is its own, drawn and moving
// like them (RemovableCard). It rests above whatever toasts are on screen
// and rises when one arrives.
//
// IPC `removable`: fixture normal | stress (switch Drives to its empty
// fixture and plug in a made-up drive) | empty | "" (live); open, eject,
// dismiss, status.
Scope {
    id: root

    property var drive: null
    property string mode: ""               // connected | opening | ejecting | safe | unsafe | failed
    property string kind: ""               // what failed: eject | open | mount | unmount
    property string reason: ""             // busy | auth | format | other
    property bool shown: false

    readonly property string name: drive ? drive.name : ""
    readonly property string text: {
        if (!drive) return "";
        if (mode === "connected") return name;
        if (mode === "opening") return "Opening · " + name;
        if (mode === "ejecting") return "Ejecting · " + name;
        if (mode === "safe") return "Safe to remove · " + name;
        if (mode === "unsafe") return "Removed without ejecting · " + name;
        if (mode === "failed") {
            const eject = kind === "eject" || kind === "unmount";
            const what = reason === "busy" ? (eject ? "In use" : "Busy") : reason === "auth" ? "Not allowed" : reason === "format" ? "Can't read it" : eject ? "Couldn't eject" : "Couldn't open";
            return what + " · " + name;
        }
        return "";
    }
    readonly property string detail: mode === "connected" && drive && drive.size > 0 ? " · " + Drives.bytes(drive.size) : ""
    readonly property string icon: mode === "safe" ? "check" : mode === "unsafe" || mode === "failed" ? "info" : mode === "ejecting" ? "eject"
                                 : drive && drive.kind !== "usb" ? "drive" : "usb"
    readonly property bool canOpen: !!drive && (drive.volumes || []).some(v => !v.locked && v.fstype)
    readonly property var actions: mode === "connected" ? (canOpen ? ["Open", "Eject"] : ["Eject"])
                                 : mode === "failed" && (kind === "eject" || kind === "unmount") ? ["Try again"] : []

    function show(d, m) { drive = d; mode = m; shown = true; stay.restart(); }
    function hide() { shown = false; }
    function act(label) {
        if (!drive) return;
        if (label === "Open") {
            const live = Drives.drive(drive.id);
            if (live && live.volumes.some(v => v.mount)) { Drives.open(drive.id, ""); hide(); return; }
            mode = "opening";
            Drives.open(drive.id, "");
        } else if (label === "Eject" || label === "Try again") eject();
    }
    function eject() {
        if (!drive || !Drives.drive(drive.id)) { hide(); return; }
        mode = "ejecting";
        Drives.eject(drive.id);
    }

    Connections {
        target: Drives
        function onAdded(d) { root.show(d, "connected"); }
        function onEjected(d) { root.show(d, "safe"); }
        function onUnplugged(d, wasMounted) {
            if (wasMounted) root.show(d, "unsafe");
            else if (root.shown && root.drive && root.drive.id === d.id) root.hide();
        }
        // Failures of what this card started; Settings shows its own.
        function onFailed(d, kind, reason) {
            if (!root.shown || !root.drive || root.drive.id !== d.id || (root.mode !== "ejecting" && root.mode !== "opening")) return;
            root.kind = kind;
            root.reason = reason;
            root.show(d, "failed");
        }
    }
    // An eject started in Settings while the card shows that drive; an open
    // that finished.
    readonly property string driveBusy: drive ? (Drives.busy[drive.id] || "") : ""
    onDriveBusyChanged: {
        if (driveBusy === "eject" && shown && mode === "connected") mode = "ejecting";
        if (driveBusy === "" && mode === "opening") Qt.callLater(() => { if (root.mode === "opening" && root.driveBusy === "") root.hide(); });
    }

    Timer {
        id: stay
        interval: root.mode === "safe" ? 4000 : root.mode === "unsafe" ? 7000 : 8000
        running: root.shown && root.mode !== "ejecting" && root.mode !== "opening" && !card.hovered
        onTriggered: root.hide()
    }

    IpcHandler {
        target: "removable"
        function fixture(name: string): void {
            if (name === "normal" || name === "stress") {
                Drives.setFixture("empty");
                Drives.plug(name === "stress" ? "long" : "usb");
                return;
            }
            root.hide();
            Drives.setFixture(name === "empty" ? "empty" : "");
        }
        function open(): void { if (root.shown && root.actions.indexOf("Open") >= 0) root.act("Open"); }
        function eject(): void { if (root.shown && (root.actions.indexOf("Eject") >= 0 || root.actions.indexOf("Try again") >= 0)) root.eject(); }
        function dismiss(): void { root.hide(); }
        function status(): string { return JSON.stringify({ "shown": root.shown, "mode": root.mode, "text": root.text + root.detail, "actions": root.actions }); }
    }

    PanelWindow {
        id: win
        screen: Shell.screenFor(Quickshell.screens)
        visible: root.shown || !card.gone
        color: "transparent"
        anchors.bottom: true
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: 600
        implicitHeight: 90 + 4 * (48 + 8) + 40
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "folio:removable"
        mask: Region { item: card.leaving ? null : card.surface }
        BackgroundEffect.blurRegion: Region { item: card.printed ? card.surface : null; radius: Theme.rL }

        // The band Folio's toasts rest on and the dock's top edge they rise
        // from (Modules/Toasts); this card sits above the toasts showing.
        readonly property real restBottom: height - 90
        readonly property real dockTop: height - 78
        readonly property int below: Math.min(3, Toasts.items.length)
        readonly property real slot: restBottom - (below + 1) * 48 - below * 8

        Item {
            width: parent.width
            height: win.dockTop
            clip: true

            RemovableCard {
                id: card
                leaving: !root.shown
                text: root.text
                detail: root.detail
                icon: root.icon
                actions: root.actions
                working: root.mode === "ejecting" || root.mode === "opening"
                x: Math.round((win.width - width) / 2)
                targetY: win.slot - pad
                startY: (win.below === 0 ? win.dockTop + 4 : win.slot + 48 + 8) - pad
                onActed: i => root.act(root.actions[i])
                onClosed: root.hide()
            }
        }
    }
}
