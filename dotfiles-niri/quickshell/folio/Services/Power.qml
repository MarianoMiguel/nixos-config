pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Session actions, and the machine's power policy for Settings › Power &
// battery and PowerAlerts.
//
// Session actions: nothing asks "are you sure?": each final action counts
// down in a toast that can be cancelled. Sleeping always locks first. All of
// them go through Sys.run (Niri.quit too), so the harness only records them.
//
// Policy: the power mode (power-profiles-daemon), what closing the lid does
// (logind, decided by NixOS in modules/nixos/power.nix), and what a low
// battery does (UPower's thresholds and its critical action). Read only,
// except the mode, which goes through Sys.run (recorded in the harness).
//
// IPC `power`: fixture normal|stress|empty ("" for live) pins all of it and
// Battery's details; mode NAME and limit true|false act like the page's
// controls (inside a fixture they change only the fixture).
Singleton {
    id: root

    function lock() { Session.lock(); }
    function hibernate() { Session.lockThen(["systemctl", "hibernate"]); }
    function logout() { Toasts.countdown("Logging out", () => Niri.quit(), 5, "user"); }
    function reboot() { Toasts.countdown("Restarting", () => Sys.run(["systemctl", "reboot"]), 5, "reload"); }
    function poweroff() { Toasts.countdown("Shutting down", () => Sys.run(["systemctl", "poweroff"]), 5, "power"); }

    // ------------------------------------------------------------ policy

    readonly property var profiles: ["power-saver", "balanced", "performance"]
    property var probed: ({})               // the last policy probe
    property bool alertsActive: false       // the PowerAlerts module is loaded

    readonly property bool daemon: probed.ppd === "1"
    readonly property var liveMode: {
        if (!daemon) return { "available": false, "profile": "", "hasPerformance": false, "degraded": "", "holds": [], "auto": probed.autoProfile === "1" };
        const holds = [], hs = PowerProfiles.holds || [];
        for (let i = 0; i < hs.length; i++) holds.push({ "profile": profiles[hs[i].profile] || "", "app": hs[i].applicationId || "", "reason": hs[i].reason || "" });
        return {
            "available": true,
            "profile": profiles[PowerProfiles.profile] || "",
            "hasPerformance": PowerProfiles.hasPerformanceProfile,
            "degraded": ["", "lap", "hot"][PowerProfiles.degradationReason] || "",
            "holds": holds,
            "auto": probed.autoProfile === "1"
        };
    }
    readonly property var livePolicy: {
        const pct = (k, d) => probed[k] !== undefined && probed[k] !== "" && !isNaN(Number(probed[k])) ? Number(probed[k]) : d;
        return {
            "hasLid": probed.hasLid === "1",
            "lid": probed.lid || "",
            "lidAC": probed.lidAC || "",
            "lidDocked": probed.lidDocked || "",
            "idleAction": probed.idleAction || "",
            // UPower's own defaults when its config cannot be read.
            "lowAt": pct("PercentageLow", 20),
            "criticalAt": pct("PercentageCritical", 5),
            "actionAt": pct("PercentageAction", 2),
            "criticalAction": probed.criticalAction || probed.CriticalPowerAction || ""
        };
    }

    property var fx: null
    property string fixture: ""
    readonly property var mode: fx ? fx.mode : liveMode
    readonly property var policy: fx ? fx.policy : livePolicy

    // What logind's lid actions and UPower's critical action do, in words.
    function lidWords(a) {
        return ({
            "ignore": "Stays on", "lock": "Locks", "hibernate": "Hibernates", "suspend": "Sleeps",
            "hybrid-sleep": "Sleeps and hibernates", "suspend-then-hibernate": "Sleeps, then hibernates",
            "poweroff": "Shuts down", "halt": "Halts", "reboot": "Restarts", "kexec": "Restarts", "sleep": "Sleeps"
        })[a] || (a ? a : "Unknown");
    }
    function criticalWords(a) {
        return ({ "Hibernate": "hibernates", "HybridSleep": "sleeps and hibernates", "PowerOff": "shuts down", "Suspend": "sleeps", "Ignore": "" })[a] || "";
    }
    function profileLabel(p) { return ({ "power-saver": "Power Saver", "balanced": "Balanced", "performance": "Performance" })[p] || p; }

    function setProfile(p) {
        if (profiles.indexOf(p) < 0) return;
        if (fx) { fx = Object.assign({}, fx, { "mode": Object.assign({}, fx.mode, { "profile": p }) }); return; }
        if (!daemon || mode.profile === p) return;
        Sys.run(["powerprofilesctl", "set", p]);
    }

    function refresh() { if (!probe.running) probe.running = true; }
    Component.onCompleted: refresh()

    Process {
        id: probe
        command: ["sh", "-c", `
            prop() { busctl --system get-property "$1" "$2" "$3" "$4" 2>/dev/null | sed 's/^[a-z]* //; s/"//g'; }
            m() { prop org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager "$1"; }
            echo "lid=$(m HandleLidSwitch)"
            echo "lidAC=$(m HandleLidSwitchExternalPower)"
            echo "lidDocked=$(m HandleLidSwitchDocked)"
            echo "idleAction=$(m IdleAction)"
            ls /proc/acpi/button/lid/*/state >/dev/null 2>&1 && echo "hasLid=1"
            [ -r /etc/UPower/UPower.conf ] && grep -E '^(PercentageLow|PercentageCritical|PercentageAction|CriticalPowerAction)=' /etc/UPower/UPower.conf
            echo "criticalAction=$(busctl --system call org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower GetCriticalAction 2>/dev/null | sed 's/^s //; s/"//g')"
            if [ -n "$(prop org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile)" ] \
                || [ -n "$(prop net.hadess.PowerProfiles /net/hadess/PowerProfiles net.hadess.PowerProfiles ActiveProfile)" ]; then echo "ppd=1"; fi
            [ "$(systemctl show -p LoadState --value power-profile-auto.service 2>/dev/null)" = loaded ] && echo "autoProfile=1"
            true`]
        stdout: StdioCollector {
            onStreamFinished: {
                const kv = {};
                for (const line of text.split("\n")) {
                    const at = line.indexOf("=");
                    if (at > 0) kv[line.slice(0, at).trim()] = line.slice(at + 1).trim();
                }
                root.probed = kv;
            }
        }
    }

    // ------------------------------------------------------------ fixtures

    readonly property var fixtures: ({
        "normal": {
            "mode": { "available": true, "profile": "balanced", "hasPerformance": true, "degraded": "", "holds": [], "auto": true },
            "policy": { "hasLid": true, "lid": "hibernate", "lidAC": "ignore", "lidDocked": "ignore", "idleAction": "ignore",
                        "lowAt": 20, "criticalAt": 5, "actionAt": 2, "criticalAction": "Hibernate" }
        },
        "stress": {
            "mode": { "available": true, "profile": "performance", "hasPerformance": true, "degraded": "hot", "auto": true,
                      "holds": [{ "profile": "power-saver", "app": "org.freedesktop.UPower.PowerProfiles.BatteryGuardianWithAnUnreasonablyLongApplicationId",
                                  "reason": "Battery is critically low; holding Power Saver until a charger is connected again and the pack has cooled down" }] },
            "policy": { "hasLid": true, "lid": "suspend-then-hibernate", "lidAC": "hibernate", "lidDocked": "ignore", "idleAction": "ignore",
                        "lowAt": 25, "criticalAt": 10, "actionAt": 3, "criticalAction": "PowerOff" }
        },
        // A desktop: no battery, no lid, no power-profiles-daemon.
        "empty": {
            "mode": { "available": false, "profile": "", "hasPerformance": false, "degraded": "", "holds": [], "auto": false },
            "policy": { "hasLid": false, "lid": "", "lidAC": "", "lidDocked": "", "idleAction": "ignore",
                        "lowAt": 20, "criticalAt": 5, "actionAt": 2, "criticalAction": "" }
        }
    })
    function setFixture(name) {
        const f = fixtures[name];
        fixture = f ? name : "";
        fx = f ? JSON.parse(JSON.stringify(f)) : null;
        Battery.setFixture(fixture);
    }

    IpcHandler {
        target: "power"
        function fixture(name: string): void { root.setFixture(name); }
        function mode(name: string): void { root.setProfile(name); }
        function limit(on: bool): void { Battery.setLimit(on); }
        function refresh(): void { root.refresh(); Battery.refresh(); }
        function status(): string {
            const b = Object.assign({}, Battery.info);
            b.history = (b.history || []).length + " points";
            return JSON.stringify({ "fixture": root.fixture, "mode": root.mode, "policy": root.policy, "battery": b, "alerts": root.alertsActive }, null, 1);
        }
    }
}
