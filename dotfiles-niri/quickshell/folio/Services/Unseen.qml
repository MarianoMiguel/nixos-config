pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common

// Whether anyone can see the shell, so what moves on its own can stop when
// nobody could tell. The lock covers the desktop while Session.locked, and
// the screens go off a while after locking (the Idle module's policy,
// Settings "idle.screensOff": niri powers them off, any input brings them
// back). Desktop surfaces wait on `desktop`; the lock's own page, which is
// what a locked screen shows, waits on `screensOff` alone.
Singleton {
    id: root

    // The login screen (folio-greeter) shares the widgets but has no lock:
    // there nothing is ever covered, and Session is never started.
    readonly property bool lockable: !Quickshell.env("FOLIO_GREETER_STATE")

    // The screens are off: the same idle timeout as Idle's power-off, also
    // counted from the lock, so both turn together; input ends both.
    readonly property bool screensOff: forced !== "" ? forced === "off" : dark.enabled && dark.isIdle
    // Nothing on the desktop can be seen: the lock is over it, or the screens are off.
    readonly property bool desktop: lockable && (Session.locked || screensOff)

    readonly property int offAfter: Settings.get("idle.screensOff")
    IdleMonitor {
        id: dark
        enabled: root.lockable && root.offAfter > 0 && Session.locked && !Awake.on
        timeout: Math.max(1, root.offAfter)
        respectInhibitors: true
    }

    // Tests: "off" or "on" pins the screens, anything else follows the policy.
    property string forced: ""
    IpcHandler {
        target: "unseen"
        function status(): string {
            return JSON.stringify({ "locked": root.lockable && Session.locked, "screensOff": root.screensOff, "desktop": root.desktop, "forced": root.forced });
        }
        function screens(state: string): void { root.forced = state === "off" || state === "on" ? state : ""; }
    }
}
