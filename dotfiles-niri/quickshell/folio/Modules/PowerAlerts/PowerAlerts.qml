import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

// Low-battery alerts, the part that waits for you. The island flashes and the
// bar's figure turns red at 10 %, but only for a moment; these toasts follow
// UPower's own thresholds (Services/Power policy): a reminder at its low
// level, offering Power Saver, and at its critical level a warning that stays
// until the charger is in and says what UPower does at the last level
// (hibernates, on Bonhart). Each fires once per discharge; plugging in takes
// them away. No window of its own: Toasts draws them.
//
// IPC `poweralerts`: fixture normal (low) | stress (critical) | empty (plugged
// in, clears) | "" (live); status. Battery's fixtures (power fixture …)
// drive it too, so the page and the alert can be tested together.
Scope {
    id: root

    property var fx: null
    readonly property var b: fx || Battery.info
    readonly property var policy: Power.policy
    readonly property bool draining: !!b.present && !!b.onBattery && b.state !== "charging" && b.state !== "full" && b.state !== "pending"
    // 0 fine, 1 low, 2 critical.
    readonly property int stage: !draining ? 0 : b.percent <= policy.criticalAt ? 2 : b.percent <= policy.lowAt ? 1 : 0

    property int told: 0                    // the highest stage shown this discharge
    property int lowToast: 0
    property int criticalToast: 0

    Component.onCompleted: { Power.alertsActive = true; Qt.callLater(evaluate); }
    Component.onDestruction: Power.alertsActive = false
    onStageChanged: evaluate()
    // A charger ends the discharge: the warnings go and the next one counts again.
    onDrainingChanged: if (!draining) clear()
    // The charger going in or out has a sound; the first reading does not.
    readonly property bool onBattery: !!b.onBattery
    property bool armed: false
    Timer { running: true; interval: 3000; onTriggered: root.armed = true }
    onOnBatteryChanged: if (armed) Sounds.play(onBattery ? "unplug" : "plug")

    function clear() {
        if (lowToast) Toasts.take(lowToast);
        if (criticalToast) Toasts.take(criticalToast);
        lowToast = 0; criticalToast = 0; told = 0;
    }
    function evaluate() {
        if (!draining) { clear(); return; }
        // Back above the low level (a fresh reading, a fixture): start over.
        if (stage === 0) { if (b.percent > policy.lowAt + 2) clear(); return; }
        if (stage < told && criticalToast) { Toasts.take(criticalToast); criticalToast = 0; told = stage; }
        if (stage <= told) return;
        told = stage;
        if (stage === 1) low(); else critical();
    }
    function left() { const d = Battery.duration(b.timeToEmpty); return d ? "about " + d + " left" : "plug in soon"; }

    function low() {
        const m = Power.mode;
        const offer = m.available && m.profile !== "power-saver";
        Sounds.play("low-battery");
        lowToast = Toasts.show("Battery at " + b.percent + "% · " + left(), {
            "icon": "battery", "timeout": 15000,
            "action": offer ? "Power Saver" : "",
            "onAction": offer ? () => Power.setProfile("power-saver") : null
        });
    }
    function critical() {
        if (lowToast) { Toasts.take(lowToast); lowToast = 0; }
        const what = Power.criticalWords(policy.criticalAction);
        const when = b.percent > policy.actionAt ? " at " + policy.actionAt + "%" : " any moment";
        const text = "Battery at " + b.percent + "% · plug in now" + (what && policy.actionAt > 0 ? ", it " + what + when : "");
        // Stays until the charger is in (or it is closed).
        Sounds.play("low-battery");
        criticalToast = Toasts.show(text, { "icon": "battery", "timeout": 3600000 });
    }

    readonly property var fixtures: ({
        "normal": { "present": true, "percent": 18, "state": "discharging", "onBattery": true, "timeToEmpty": 3900 },
        "stress": { "present": true, "percent": 3, "state": "discharging", "onBattery": true, "timeToEmpty": 140 },
        "empty": { "present": true, "percent": 4, "state": "charging", "onBattery": false, "timeToEmpty": 0 }
    })

    IpcHandler {
        target: "poweralerts"
        function fixture(name: string): void {
            root.clear();
            root.fx = root.fixtures[name] || null;
            Qt.callLater(root.evaluate);
        }
        function status(): string {
            return JSON.stringify({ "fixture": !!root.fx, "percent": root.b.percent, "draining": root.draining, "stage": root.stage, "told": root.told,
                                    "lowAt": root.policy.lowAt, "criticalAt": root.policy.criticalAt, "actionAt": root.policy.actionAt, "action": root.policy.criticalAction });
        }
    }
}
