import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services

// Idle policy, owned by the shell (Settings: screensaver.after, idle.*):
// the screensaver first, then the lock (sooner on battery), screens off a
// while after locking, and hibernation on battery. Idle inhibitors and Keep
// awake (Services/Awake) hold all of it off. The harness never powers
// anything off or hibernates; it only records what it would have done.
Scope {
    id: root

    readonly property bool harness: (Quickshell.env("FOLIO_HARNESS") || "") !== ""
    readonly property bool awake: Awake.on
    readonly property int saverAfter: Settings.get("screensaver.after")
    readonly property int lockAfter: Battery.onBattery ? Settings.get("idle.lockBattery") : Settings.get("idle.lockAC")
    readonly property int offAfter: Settings.get("idle.screensOff")
    readonly property int hibernateAfter: Settings.get("idle.hibernateBattery")
    property string last: ""                // what the policy did last (status)

    // The screensaver: up while idle; any input lifts it away.
    property bool saver: false
    property bool armed: false              // input seen since it came up counts
    property var fx: null                   // fixture caption
    function showSaver() { if (Session.locked) return; armed = false; saver = true; }
    function dismiss() { saver = false; fx = null; }
    onSaverChanged: if (!saver) armed = false

    IdleMonitor {
        enabled: root.saverAfter > 0 && !Session.locked && !root.awake
        timeout: Math.max(1, root.saverAfter)
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) root.showSaver(); else root.dismiss()
    }
    // A one-second monitor while the saver is up: idle arms it, input lifts it.
    IdleMonitor {
        enabled: root.saver
        timeout: 1
        respectInhibitors: false
        onIsIdleChanged: if (isIdle) root.armed = true; else if (root.armed) root.dismiss()
    }
    IdleMonitor {
        enabled: root.lockAfter > 0 && !Session.locked && !root.awake
        timeout: Math.max(1, root.lockAfter)
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) { root.last = "lock"; Session.lock(); }
    }
    // Counted from the lock (the monitor starts when the lock does).
    IdleMonitor {
        enabled: root.offAfter > 0 && Session.locked && !root.awake
        timeout: Math.max(1, root.offAfter)
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) root.screensOff()
    }
    IdleMonitor {
        enabled: root.hibernateAfter > 0 && Battery.onBattery && !root.awake
        timeout: Math.max(1, root.hibernateAfter)
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) root.hibernate()
    }

    // niri powers the screens back on with any input.
    function screensOff() {
        last = "screens-off";
        if (!harness) Niri.action(["power-off-monitors"]);
    }
    function hibernate() {
        last = "hibernate";
        if (harness) Session.lock();
        else Session.lockThen(["systemctl", "hibernate"]);
    }

    Connections {
        target: Session
        function onLockedChanged() { if (Session.locked) { root.saver = false; root.fx = null; } }
    }

    Variants {
        model: Quickshell.screens
        Screensaver {
            required property var modelData
            screen: modelData
            idle: root
        }
    }

    readonly property var fixtures: ({
        "normal": { "caption": "Ronin · The quiet crossing" },
        "stress": { "caption": "Azure Folio, European Summer · A Sicilian summer, with the harbour at Cefalù seen from the cathedral steps at noon in August" },
        "empty": { "caption": "" }
    })

    IpcHandler {
        target: "idle"
        function screensaver(): void { root.showSaver(); }
        function dismiss(): void { root.dismiss(); }
        function fixture(name: string): void { root.fx = root.fixtures[name] || null; root.showSaver(); }
        function status(): string {
            return JSON.stringify({ "saver": root.saver, "saverAfter": root.saverAfter, "lockAfter": root.lockAfter, "offAfter": root.offAfter,
                "hibernateAfter": root.hibernateAfter, "onBattery": Battery.onBattery, "awake": root.awake, "locked": Session.locked, "last": root.last });
        }
    }
}
