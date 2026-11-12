pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// The laptop battery through UPower.
//
// The properties at the top are the live battery for the bar, the island,
// the lock screen and the idle policy; fixtures never touch them, so a test
// can never make the idle policy think the laptop is on battery.
//
// `info` is what Settings › Power & battery and PowerAlerts read: the same
// battery plus its health (sysfs), the charge limit (modules/nixos/battery.nix)
// and the last day of charge (UPower's history). A fixture replaces it
// (IPC: power fixture normal|stress|empty, "" for live; see Services/Power).
Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool present: device && device.isLaptopBattery && device.isPresent
    readonly property int percent: device ? Math.round(device.percentage * 100) : 0
    readonly property bool charging: device && device.state === UPowerDeviceState.Charging
    readonly property bool full: device && device.state === UPowerDeviceState.FullyCharged
    readonly property bool pluggedNotCharging: device && device.state === UPowerDeviceState.PendingCharge
    readonly property bool onBattery: UPower.onBattery
    readonly property bool low: present && onBattery && percent <= 10
    readonly property bool critical: present && onBattery && percent <= 5

    // "3 h 20 m left", "42 m to full", "Charged".
    readonly property string timeLabel: {
        if (!present) return "";
        if (full) return "Charged";
        if (pluggedNotCharging) return "Plugged in, not charging";
        const s = charging ? device.timeToFull : device.timeToEmpty;
        if (!s || s <= 0) return charging ? "Charging" : "";
        const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60);
        return (h > 0 ? h + " h " : "") + m + " m" + (charging ? " to full" : " left");
    }

    // ------------------------------------------------------------ details

    // The value `battery-charge-limit health` writes (healthLimit in
    // modules/nixos/battery.nix).
    readonly property int healthLimit: 80

    // "3 h 20 m", "42 m", "under a minute".
    function duration(s) {
        if (!s || s <= 0) return "";
        if (s < 60) return "under a minute";
        const total = Math.round(s / 60), h = Math.floor(total / 60), m = total % 60;
        if (h >= 48) return Math.round(h / 24) + " days";
        return h > 0 ? h + " h" + (m > 0 ? " " + m + " m" : "") : m + " m";
    }
    // UPower's states, as words.
    function stateName(s) {
        switch (s) {
        case UPowerDeviceState.Charging: return "charging";
        case UPowerDeviceState.Discharging: return "discharging";
        case UPowerDeviceState.PendingDischarge: return "discharging";
        case UPowerDeviceState.Empty: return "empty";
        case UPowerDeviceState.FullyCharged: return "full";
        case UPowerDeviceState.PendingCharge: return "pending";
        default: return "unknown";
        }
    }
    // Maximum capacity as a share of the design capacity, or -1.
    function health(i) { return i && i.energyDesign > 0 && i.energyFull > 0 ? Math.round(i.energyFull / i.energyDesign * 100) : -1; }
    // One line on what the battery is doing: "On battery · 3 h 20 m left".
    function stateLine(i) {
        if (!i || !i.present) return "";
        const left = duration(i.timeToEmpty), toFull = duration(i.timeToFull);
        switch (i.state) {
        case "full": return "Charged";
        case "pending":
            if (i.limit > 0 && i.limit < 100 && i.percent >= i.limit - 3) return "Plugged in · held at " + i.limit + "% to spare the battery";
            return "Plugged in · not charging";
        case "charging": return toFull ? "Charging · " + toFull + " to full" : "Charging";
        case "discharging":
        case "empty": return left ? "On battery · " + left + " left" : "On battery";
        default: return i.onBattery ? "On battery" : "Plugged in";
        }
    }

    // sysfs facts (cycle count, design capacity, the threshold), read by refresh().
    property var facts: ({})
    property var history: []            // [{t: seconds, v: percent, s: UPower state}], oldest first
    property int pendingLimit: -1       // a limit just written, until sysfs agrees

    readonly property var live: ({
        "present": root.present,
        "percent": root.percent,
        "state": root.stateName(root.device ? root.device.state : 0),
        "onBattery": root.onBattery,
        "timeToEmpty": root.device ? root.device.timeToEmpty : 0,
        "timeToFull": root.device ? root.device.timeToFull : 0,
        "rate": root.device ? Math.abs(root.device.changeRate) : 0,
        "energy": root.device ? root.device.energy : 0,
        "energyFull": root.facts.energyFull || (root.device ? root.device.energyCapacity : 0),
        "energyDesign": root.facts.energyDesign || 0,
        "cycles": root.facts.cycles > 0 ? root.facts.cycles : -1,
        "vendor": root.facts.vendor || "",
        "model": root.facts.model || "",
        "technology": root.facts.technology || "",
        "limit": root.pendingLimit > 0 ? root.pendingLimit : (root.facts.limit > 0 ? root.facts.limit : -1),
        "limitWritable": !!root.facts.limitWritable && !!root.facts.helper,
        "limitHelper": !!root.facts.helper,
        "history": root.history
    })
    property var fx: null
    readonly property var info: fx || live

    // The page refreshes while it is open: watch(1) on open, watch(-1) on close.
    property int watchers: 0
    function watch(d) { watchers = Math.max(0, watchers + d); if (d > 0) refresh(); }
    function refresh() { if (!probe.running) probe.running = true; }
    Timer { interval: 60000; repeat: true; running: root.watchers > 0; onTriggered: root.refresh() }

    // The charge limit through modules/nixos/battery.nix's helper, the only
    // mechanism that may write the threshold without a password. Fixtures
    // change only themselves; the harness records the command (Sys.run).
    function setLimit(on) {
        if (fx) { fx = Object.assign({}, fx, { "limit": on ? healthLimit : 100 }); return; }
        if (!live.limitWritable) return;
        if (Sys.run(["battery-charge-limit", on ? "health" : "full"])) {
            pendingLimit = on ? healthLimit : 100;
            confirm.restart();
        }
    }
    Timer { id: confirm; interval: 1200; onTriggered: root.refresh() }
    Timer { id: giveUp; interval: 6000; onTriggered: root.pendingLimit = -1 }
    onPendingLimitChanged: if (pendingLimit > 0) giveUp.restart()

    Process {
        id: probe
        command: ["sh", "-c", `
            b=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1)
            [ -n "$b" ] || exit 0
            echo "name=$(basename "$b")"
            for f in cycle_count energy_full energy_full_design charge_full charge_full_design voltage_min_design manufacturer model_name technology; do
                [ -r "$b/$f" ] && echo "$f=$(cat "$b/$f" 2>/dev/null)"
            done
            for f in charge_control_end_threshold charge_stop_threshold charge_control_limit_max; do
                if [ -e "$b/$f" ]; then
                    echo "limit=$(cat "$b/$f" 2>/dev/null)"
                    [ -w "$b/$f" ] && echo "limit_writable=1"
                    break
                fi
            done
            command -v battery-charge-limit >/dev/null 2>&1 && echo "helper=1"
            true`]
        stdout: StdioCollector {
            onStreamFinished: {
                const kv = {};
                for (const line of text.split("\n")) {
                    const at = line.indexOf("=");
                    if (at > 0) kv[line.slice(0, at)] = line.slice(at + 1).trim();
                }
                const n = k => kv[k] !== undefined && kv[k] !== "" ? Number(kv[k]) : 0;
                // Energy in µWh; charge-based batteries report µAh at the design voltage.
                const volts = n("voltage_min_design") / 1e6;
                const full = n("energy_full") ? n("energy_full") / 1e6 : n("charge_full") * volts / 1e6;
                const design = n("energy_full_design") ? n("energy_full_design") / 1e6 : n("charge_full_design") * volts / 1e6;
                root.facts = {
                    "name": kv.name || "",
                    "cycles": n("cycle_count"),
                    "energyFull": full,
                    "energyDesign": design,
                    "vendor": kv.manufacturer || "",
                    "model": kv.model_name || "",
                    "technology": kv.technology || "",
                    "limit": kv.limit !== undefined ? n("limit") : -1,
                    "limitWritable": kv.limit_writable === "1",
                    "helper": kv.helper === "1"
                };
                if (root.pendingLimit > 0 && root.facts.limit === root.pendingLimit) root.pendingLimit = -1;
                if (kv.name) { historyProc.command = root.historyCommand(kv.name); historyProc.running = true; }
                else root.history = [];
            }
        }
    }

    // UPower keeps the charge history itself; one call returns the last day.
    function historyCommand(name) {
        return ["busctl", "--system", "--json=short", "call", "org.freedesktop.UPower",
                "/org/freedesktop/UPower/devices/battery_" + name.replace(/[^A-Za-z0-9_]/g, "_"),
                "org.freedesktop.UPower.Device", "GetHistory", "suu", "charge", "86400", "200"];
    }
    Process {
        id: historyProc
        stdout: StdioCollector {
            onStreamFinished: {
                let d;
                try { d = JSON.parse(text).data[0]; } catch (e) { root.history = []; return; }
                root.history = (d || []).filter(p => p[2] !== 0 && p[1] >= 0 && p[1] <= 100)
                    .map(p => ({ "t": p[0], "v": p[1], "s": p[2] }))
                    .sort((a, b) => a.t - b.t);
            }
        }
    }

    // ------------------------------------------------------------ fixtures

    // A day of charge every 10 minutes from a list of [hours ago, percent, state]
    // turning points (UPower states: 1 charging, 2 discharging, 4 full, 5 pending).
    function curve(stops) {
        const now = Date.now() / 1000, out = [];
        for (let i = 0; i < stops.length - 1; i++) {
            const a = stops[i], b = stops[i + 1];
            for (let h = a[0]; h > b[0]; h -= 1 / 6)
                out.push({ "t": now - h * 3600, "v": a[1] + (b[1] - a[1]) * (a[0] - h) / (a[0] - b[0]), "s": a[2] });
        }
        const last = stops[stops.length - 1];
        out.push({ "t": now - last[0] * 3600, "v": last[1], "s": last[2] });
        return out;
    }
    function fixtureData(name) {
        if (name === "normal") return {
            "present": true, "percent": 64, "state": "discharging", "onBattery": true,
            "timeToEmpty": 12000, "timeToFull": 0, "rate": 9.8, "energy": 31.3, "energyFull": 48.9, "energyDesign": 57.0,
            "cycles": 111, "vendor": "ATL", "model": "5B11M90125", "technology": "Li-poly",
            "limit": root.healthLimit, "limitWritable": true, "limitHelper": true,
            "history": curve([[24, 52, 2], [21, 31, 1], [18.5, 80, 5], [9, 80, 2], [7.5, 72, 1], [6, 80, 5], [3, 80, 2], [0, 64, 2]])
        };
        if (name === "stress") return {
            "present": true, "percent": 3, "state": "discharging", "onBattery": true,
            "timeToEmpty": 50, "timeToFull": 0, "rate": 58.3, "energy": 0.9, "energyFull": 23.4, "energyDesign": 57.0,
            "cycles": 1874, "vendor": "Sunwoda Electronic Co., Ltd. (replacement cell, third-party, unverified)",
            "model": "5B11M90125-SB10W51974-L22D4PG1-REV-B-HIGH-CAPACITY-4-CELL-POLYMER-PACK",
            "technology": "Lithium-ion polymer (prismatic, 4 cells in series)",
            "limit": 60, "limitWritable": false, "limitHelper": false,
            "history": curve([[24, 100, 4], [22, 100, 2], [20, 61, 2], [19.8, 63, 1], [19.5, 40, 2], [15, 9, 2], [14.8, 12, 1], [12, 88, 1], [11.8, 88, 2], [6, 34, 2], [5.9, 36, 1], [5.6, 33, 2], [0, 3, 2]])
        };
        if (name === "empty") return {
            "present": false, "percent": 0, "state": "unknown", "onBattery": false,
            "timeToEmpty": 0, "timeToFull": 0, "rate": 0, "energy": 0, "energyFull": 0, "energyDesign": 0,
            "cycles": -1, "vendor": "", "model": "", "technology": "", "limit": -1, "limitWritable": false, "limitHelper": false, "history": []
        };
        return null;
    }
    function setFixture(name) { fx = fixtureData(name); }
}
