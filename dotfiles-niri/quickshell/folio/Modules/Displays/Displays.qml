import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Displays: keeps the screens usable and says what changed. Outputs (the
// service) brings back each set of displays' layout; this module announces it,
// shows each display's name when asked (Identify), runs Night light, and
// never leaves a black screen: when the only connected display is off (a
// docked layout that turns the laptop panel off, then undocking), it turns
// it on.
Scope {
    id: root

    // ---------------------------------------------------------------- guard

    function check() { if (Niri.available) probe.running = true; }
    Process {
        id: probe
        // Waits inside the process: with every display off there is no window,
        // and QML timers may not tick without one.
        command: ["sh", "-c", "sleep 1.5; niri msg --json outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                let outputs;
                try { outputs = Object.values(JSON.parse(text)); } catch (e) { return; }
                const on = outputs.filter(o => o.current_mode !== null && o.current_mode !== undefined);
                if (outputs.length > 0 && on.length === 0) {
                    const panel = outputs.find(o => /^eDP/.test(o.name)) || outputs[0];
                    console.warn("Displays: no display is on; turning on", panel.name);
                    Quickshell.execDetached(["niri", "msg", "output", panel.name, "on"]);
                }
            }
        }
    }
    Connections {
        target: Quickshell
        function onScreensChanged() { root.check(); }
    }
    Component.onCompleted: check()

    // Night light runs whether Settings is open or not.
    readonly property bool nightActive: NightLight.active

    // ---------------------------------------------------------------- announce

    Connections {
        target: Outputs
        function onApplied(name) {
            if (name) Toasts.show("Displays: " + name, { "icon": "display", "action": "Change", "onAction": () => Shell.openSettings("displays") });
            else Toasts.show("New display arrangement", { "icon": "display", "action": "Arrange", "onAction": () => Shell.openSettings("displays"), "timeout": 6000 });
        }
    }

    // ---------------------------------------------------------------- identify

    Variants {
        model: Outputs.identifying ? Quickshell.screens : []
        PanelWindow {
            id: tag
            required property var modelData
            screen: modelData
            readonly property var output: Outputs.outputs.find(o => o.name === modelData.name) || (Outputs.fixture ? Outputs.outputs.filter(o => o.on)[Quickshell.screens.indexOf(modelData)] || null : null)
            anchors { top: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            implicitHeight: card.height + 120
            color: "transparent"
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "folio:identify"
            Sheet {
                id: card
                anchors.horizontalCenter: parent.horizontalCenter
                y: 72
                width: Math.max(320, Math.min(parent.width - 80, info.implicitWidth + 64))
                height: info.implicitHeight + 40
                radius: Theme.rXl
                color: Theme.sheetStrong
                opacity: 0
                scale: 0.96
                Component.onCompleted: { opacity = 1; scale = 1; }
                Behavior on opacity { NumberAnimation { duration: Theme.tQuick } }
                Behavior on scale { SpringSoft {} }
                Column {
                    id: info
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(implicitWidth, card.parent.width - 140)
                        text: tag.output ? tag.output.label : tag.modelData.name
                        font.family: Theme.ui; font.pixelSize: 44; font.weight: Font.DemiBold; color: Theme.ink
                        elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                    }
                    Cap {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                            const o = tag.output, m = o ? Outputs.parseMode(o.mode) : null;
                            return o && m ? [o.name, m.w + " × " + m.h, Math.round(m.hz) + " Hz", Math.round(o.scale * 100) + "%"].join(" · ") : tag.modelData.name;
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- IPC

    IpcHandler {
        target: "displays"
        function open(): void { Shell.openSettings("displays"); }
        // The next remembered layout for the displays connected now.
        function cycle(): string { return Outputs.cycle(); }
        function identify(): void { Outputs.identify(); }
        function fixture(name: string): void { Outputs.setFixture(name); }
        function state(): string {
            return JSON.stringify({
                "outputs": Outputs.outputs.map(o => [o.name, o.on ? o.mode : "off", o.x, o.y, o.scale, o.transform].join(" ")),
                "active": Outputs.active ? Outputs.active.name : "",
                "layouts": Outputs.current.map(l => l.name),
                "others": Outputs.others.map(l => l.name),
                "auto": Outputs.auto, "keepPending": !!Outputs.keep, "lidClosed": Outputs.lidClosed, "clamped": Outputs.clamped, "night": NightLight.active, "nightTemp": Math.round(NightLight.temp)
            }, null, 1);
        }
        function kdl(): string { return Outputs.written; }
        function choose(name: string): bool { const l = Outputs.current.find(x => x.name === name); return l ? Outputs.choose(l.id) : false; }
        // Tests: change one display by connector name: set DP-3 scale 1.25
        function set(name: string, prop: string, value: string): bool {
            const o = Outputs.outputs.find(x => x.name === name);
            if (!o) return false;
            const patch = {};
            patch[prop] = prop === "scale" ? +value : prop === "off" || prop === "vrr" ? value === "true" : value;
            return Outputs.change(o.key, patch);
        }
        function move(name: string, x: int, y: int): bool {
            const o = Outputs.outputs.find(v => v.name === name);
            if (!o) return false;
            const p = {};
            p[o.key] = { "x": x, "y": y };
            return Outputs.arrange(p);
        }
        function keep(): void { Outputs.keepChanges(); }
        function plug(name: string): void { Outputs.plug(name, true); }
        function unplug(name: string): void { Outputs.plug(name, false); }
        function saveAs(name: string): string { return Outputs.saveAs(name); }
        function forget(name: string): void { const l = Outputs.layouts.find(x => x.name === name); if (l) Outputs.forget(l.id); }
        function auto(on: bool): void { Outputs.setAuto(on); }
        // niri's lid switch (Folio's binds): closed with another display on turns the panel off.
        function lid(closed: bool): void { Outputs.setLid(closed); }
        // Night light: off | sunset | custom | always
        function night(schedule: string): string { Settings.set("night.schedule", schedule); return NightLight.active ? "on" : "off"; }
    }
}
