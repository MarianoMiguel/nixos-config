pragma Singleton
import QtQuick
import Quickshell

// Commands that change the system (connect a network, pair a device, set a
// default app) go through run(). In the harness they are only recorded, so
// tests never touch the real machine; `settings dryrun` lists them.
Singleton {
    id: root
    readonly property bool harness: !!Quickshell.env("FOLIO_HARNESS")
    property var log: []

    // Runs cmd detached; returns false (and records it) in the harness.
    function run(cmd) {
        if (harness) {
            console.warn("dry-run:", JSON.stringify(cmd));
            log = log.concat([cmd]).slice(-50);
            return false;
        }
        Quickshell.execDetached(cmd);
        return true;
    }
}
