pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Lock state for the whole shell. The Lock module draws the lock screen when
// locked is true. logind's Lock signal (loginctl lock-session) and its
// PrepareForSleep both lock, so resuming never shows the desktop first.
Singleton {
    id: root

    property bool locked: false
    signal unlocked()

    function lock() { locked = true; }
    function unlock() { locked = false; unlocked(); }

    // Lock first, then sleep once the lock screen is up.
    function lockThen(command) {
        lock();
        pending = command;
        sleepAfterLock.restart();
    }
    property var pending: null
    Timer {
        id: sleepAfterLock
        interval: 700
        onTriggered: {
            if (!root.pending) return;
            if (Quickshell.env("FOLIO_HARNESS")) console.warn("Session: would run", root.pending.join(" "));
            else Quickshell.execDetached(root.pending);
            root.pending = null;
        }
    }

    Process {
        running: !Quickshell.env("FOLIO_HARNESS")
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1"]
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("PrepareForSleep (true") >= 0 || line.indexOf(".Session.Lock ()") >= 0) root.lock();
                else if (line.indexOf(".Session.Unlock ()") >= 0) root.unlock();
            }
        }
    }
}
