import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// Displays: arrange the displays, set each one's resolution, refresh rate,
// scale and rotation, keep layouts for each set of displays, and Night light.
// Outputs (the service) applies and remembers; changes that could leave a
// screen unreadable revert by themselves unless kept.
SettingsPage {
    id: page
    title: "Displays"
    description: "Drag the displays to match your desk. Interstellar remembers the arrangement for the displays connected now and brings it back when they connect again."

    property string selected: ""
    readonly property var sel: Outputs.outputFor(selected) || Outputs.outputs.find(o => o.on) || Outputs.outputs[0] || null
    Component.onCompleted: Outputs.refresh()

    function hz(v) { return Math.abs(v - Math.round(v)) < 0.05 ? Math.round(v) + " Hz" : v.toFixed(2) + " Hz"; }
    readonly property var curMode: sel ? Outputs.parseMode(sel.mode) : null
    // Resolutions, largest first; refresh rates for the current one.
    readonly property var sizes: {
        if (!sel) return [];
        const seen = {}, out = [];
        for (const m of sel.modes) {
            const k = m.w + "x" + m.h;
            if (seen[k]) continue;
            seen[k] = true;
            out.push({ "w": m.w, "h": m.h, "preferred": sel.modes.some(x => x.preferred && x.w === m.w && x.h === m.h) });
        }
        return out.sort((a, b) => b.w * b.h - a.w * a.h || b.w - a.w);
    }
    readonly property var rates: sel && curMode ? sel.modes.filter(m => m.w === curMode.w && m.h === curMode.h).sort((a, b) => b.hz - a.hz) : []
    function pickSize(w, h) {
        const same = sel.modes.filter(m => m.w === w && m.h === h);
        const keep = same.find(m => curMode && Math.abs(m.hz - curMode.hz) < 0.5);
        const pref = same.find(m => m.preferred);
        Outputs.change(sel.key, { "mode": (keep || pref || same.sort((a, b) => b.hz - a.hz)[0]).id });
    }
    readonly property var scales: {
        const s = [1, 1.25, 1.5, 1.75, 2];
        if (sel && s.every(v => Math.abs(v - sel.scale) > 0.001)) s.push(sel.scale);
        return s.sort((a, b) => a - b).map(v => ({ "value": v, "label": Math.round(v * 100) + "%" }));
    }
    readonly property string looksLike: {
        if (!sel || !curMode) return "";
        const rot = Outputs.rotated(sel.transform);
        const w = Math.round((rot ? curMode.h : curMode.w) / sel.scale), h = Math.round((rot ? curMode.w : curMode.h) / sel.scale);
        return "Looks like " + w + " × " + h;
    }
    property bool pickingSize: false
    onSelChanged: pickingSize = false
    property string renaming: ""

    Notice {
        visible: !Outputs.available
        Layout.topMargin: 12
        icon: "display"
        text: "Display settings need niri. This session is not running it."
    }

    // ------------------------------------------------------------ the desk
    Rectangle {
        visible: Outputs.available
        Layout.fillWidth: true
        Layout.topMargin: 12
        Layout.preferredHeight: 340
        radius: Theme.rL
        color: Theme.wash
        border.color: Theme.rule
        DisplayCanvas {
            anchors { fill: parent; margins: 12; bottomMargin: 52 }
            outputs: Outputs.outputs
            selected: page.sel ? page.sel.key : ""
            onSelect: key => page.selected = key
            onMoved: positions => Outputs.arrange(positions)
        }
        RowLayout {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
            spacing: 10
            Button { icon: "eye"; text: "Identify"; onClicked: Outputs.identify() }
            Item { Layout.fillWidth: true }
            Cap {
                text: Outputs.active ? "Layout · " + Outputs.active.name : (Outputs.outputs.length > 1 ? "Not saved yet: change anything to keep it" : "")
                Layout.maximumWidth: 360
            }
        }
    }

    // ------------------------------------------------------------ the display
    Section {
        visible: !!page.sel
        title: page.sel ? page.sel.label : ""
        hint: page.sel ? [page.sel.builtin ? "Built-in" : (page.sel.make || ""), page.sel.name, page.sel.inches > 0 ? page.sel.inches.toFixed(1) + "″" : ""].filter(x => x).join(" · ") : ""
    }
    Card {
        visible: !!page.sel
        divided: true
        SettingRow {
            icon: "display"; label: "Use this display"
            hint: page.sel && page.sel.builtin && Outputs.clamped ? "The lid is closed, so it is off until the lid opens."
                  : page.sel && page.sel.on && Outputs.onCount === 1 ? "The only display that is on stays on."
                  : (page.sel && !page.sel.on ? "Off: windows stay on the other displays." : "")
            Toggle {
                checked: !!page.sel && page.sel.on
                enabled: !!page.sel && !(page.sel.on && Outputs.onCount === 1)
                opacity: enabled ? 1 : 0.45
                onToggled: v => Outputs.change(page.sel.key, { "off": !v })
            }
        }
        SettingRow {
            visible: !!page.sel && page.sel.on
            icon: "grid"; label: "Resolution"
            hint: page.sel && page.sel.mode === page.sel.preferredMode ? "The display's own resolution." : ""
            Button {
                icon: page.pickingSize ? "close" : "down"
                text: page.curMode ? page.curMode.w + " × " + page.curMode.h : ""
                onClicked: page.pickingSize = !page.pickingSize
            }
        }
        Flow {
            visible: page.pickingSize && !!page.sel && page.sel.on
            Layout.fillWidth: true
            Layout.leftMargin: 56; Layout.rightMargin: 14; Layout.bottomMargin: 12
            spacing: 6
            Repeater {
                model: page.sizes
                Rectangle {
                    id: sizeChip
                    required property var modelData
                    readonly property bool on: page.curMode && modelData.w === page.curMode.w && modelData.h === page.curMode.h
                    width: chip.implicitWidth + 20; height: 30; radius: Theme.rS
                    activeFocusOnTab: true
                    Keys.onPressed: event => KeyNav.press(event, () => { page.pickingSize = false; if (!sizeChip.on) page.pickSize(sizeChip.modelData.w, sizeChip.modelData.h); })
                    FocusRing { radius: Theme.rS }
                    color: on ? Theme.ink : (chipArea.containsMouse ? Theme.wellStrong : Theme.sheetStrong)
                    border.width: on ? 0 : 1; border.color: Theme.rule
                    Label {
                        id: chip; anchors.centerIn: parent
                        text: modelData.w + " × " + modelData.h + (modelData.preferred ? "  ·  native" : "")
                        font.pixelSize: Theme.fsS; color: parent.on ? Theme.inkText : Theme.text
                    }
                    MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { page.pickingSize = false; if (!parent.on) page.pickSize(modelData.w, modelData.h); } }
                }
            }
        }
        SettingRow {
            visible: !!page.sel && page.sel.on && page.rates.length > 1
            icon: "reload"; label: "Refresh rate"
            Choice {
                options: page.rates.slice(0, 5).map(m => ({ "value": m.id, "label": page.hz(m.hz) }))
                value: page.sel ? page.sel.mode : ""
                onChosen: v => Outputs.change(page.sel.key, { "mode": v })
            }
        }
        SettingRow {
            visible: !!page.sel && page.sel.on
            icon: "sparkle"; label: "Scale"; hint: page.looksLike
            Choice {
                options: page.scales
                value: page.sel ? page.scales.map(s => s.value).find(v => Math.abs(v - page.sel.scale) < 0.001) : 1
                onChosen: v => Outputs.change(page.sel.key, { "scale": v })
            }
        }
        SettingRow {
            visible: !!page.sel && page.sel.on
            icon: "reload"; label: "Rotation"
            Choice {
                options: [{ "value": "normal", "label": "None" }, { "value": "90", "label": "90°" }, { "value": "180", "label": "180°" }, { "value": "270", "label": "270°" }]
                value: page.sel ? page.sel.transform : "normal"
                onChosen: v => Outputs.change(page.sel.key, { "transform": v })
            }
        }
        SettingRow {
            visible: !!page.sel && page.sel.on && page.sel.vrrSupported
            icon: "bolt"; label: "Variable refresh rate"; hint: "Smoother games and video; some displays flicker with it."
            Toggle { checked: !!page.sel && page.sel.vrr; onToggled: v => Outputs.change(page.sel.key, { "vrr": v }) }
        }
    }

    // ------------------------------------------------------------ layouts
    Section {
        visible: Outputs.available && Outputs.outputs.length > 0
        title: "Layouts for these displays"
        hint: "The latest one comes back when these displays connect. Keep more than one to switch between them."
        Component.onCompleted: page.mark("layouts", this)
    }
    Card {
        visible: Outputs.available && Outputs.outputs.length > 0
        divided: true
        Repeater {
            model: Outputs.current
            ListRow {
                id: row
                required property var modelData
                icon: "display"
                title: modelData.name
                subtitle: Outputs.summary(modelData)
                selected: Outputs.active !== null && Outputs.active.id === modelData.id
                onClicked: if (!selected) Outputs.choose(modelData.id)
                Row {
                    spacing: 4
                    Button { icon: "pencil"; onClicked: { page.renaming = row.modelData.id; renameField.text = row.modelData.name; renameField.focusNow(); } }
                    Button { icon: "close"; onClicked: Outputs.forget(row.modelData.id) }
                }
            }
        }
        RowLayout {
            visible: page.renaming !== ""
            Layout.fillWidth: true; Layout.margins: 12; spacing: 8
            Field {
                id: renameField
                Layout.fillWidth: true
                placeholder: "Layout name"
                onAccepted: t => { Outputs.rename(page.renaming, t); page.renaming = ""; }
                onCancelled: page.renaming = ""
            }
            Button { text: "Rename"; primary: true; onClicked: { Outputs.rename(page.renaming, renameField.text); page.renaming = ""; } }
        }
        ListRow {
            icon: "plus"
            title: Outputs.current.length ? "Save as a new layout" : "Save this layout"
            subtitle: Outputs.current.length ? "A copy of this one under its own name; changes from then on go to it." : "So it comes back the next time these displays connect."
            onClicked: { const id = Outputs.saveAs(""); page.renaming = id; renameField.text = (Outputs.layouts.find(l => l.id === id) || {}).name || ""; renameField.focusNow(); }
        }
    }
    Card {
        visible: Outputs.available
        Layout.topMargin: 10
        divided: true
        SettingRow {
            icon: "link"; label: "Switch layouts by themselves"
            hint: "When displays connect or disconnect, bring back their latest layout."
            Toggle { checked: Outputs.auto; onToggled: v => Outputs.setAuto(v) }
        }
        SettingRow {
            visible: Outputs.outputs.some(o => o.builtin)
            icon: "laptop"; label: "Closing the lid turns the built-in display off"
            hint: "Only while another display is on; layouts stay as they are."
            Toggle { checked: Outputs.clamshell; onToggled: v => Settings.set("displays.clamshell", v) }
        }
    }

    Section {
        visible: Outputs.others.length > 0
        title: "Remembered for other displays"
        hint: "They come back when those displays are connected."
    }
    Card {
        visible: Outputs.others.length > 0
        divided: true
        Repeater {
            model: Outputs.others
            ListRow {
                required property var modelData
                icon: "display"; clickable: false; dim: true
                title: modelData.name
                subtitle: Outputs.displayNames(modelData)
                Button { icon: "close"; onClicked: Outputs.forget(modelData.id) }
            }
        }
    }

    // ------------------------------------------------------------ night light
    Section {
        title: "Night light"
        hint: NightLight.schedule === "sunset" && NightLight.sun
              ? "Warmer colors from " + Qt.formatTime(NightLight.sun.sunset, "HH:mm") + " to " + Qt.formatTime(NightLight.sun.sunrise, "HH:mm") + " in " + NightLight.place[0] + "."
              : "Warmer colors in the evening, easier on the eyes."
        Component.onCompleted: page.mark("night", this)
    }
    Card {
        divided: true
        SettingRow {
            icon: "moon"; label: "Schedule"
            hint: NightLight.active ? "On now." : (NightLight.snoozed ? "Paused until the schedule changes." : "")
            Choice {
                options: [{ "value": "off", "label": "Off" }, { "value": "sunset", "label": "Sunset" }, { "value": "custom", "label": "Hours" }, { "value": "always", "label": "Always" }]
                value: NightLight.schedule
                onChosen: v => Settings.set("night.schedule", v)
            }
        }
        SettingRow {
            visible: NightLight.schedule === "custom"
            icon: "calendar"; label: "Hours"; hint: "24-hour times; it may run past midnight."
            Row {
                spacing: 8
                Field { width: 82; text: Settings.get("night.from"); placeholder: "22:00"; onAccepted: t => { if (NightLight.minutes(t) >= 0) Settings.set("night.from", t); } }
                Label { text: "to"; color: Theme.text2; anchors.verticalCenter: parent.verticalCenter }
                Field { width: 82; text: Settings.get("night.to"); placeholder: "07:00"; onAccepted: t => { if (NightLight.minutes(t) >= 0) Settings.set("night.to", t); } }
            }
        }
        SettingRow {
            visible: NightLight.schedule !== "off"
            icon: "sun"; label: "Warmth"; hint: NightLight.nightTemp + " K"
            Slider { implicitWidth: 220; value: NightLight.warmth; onMoved: v => Settings.set("night.warmth", Math.round(v * 100) / 100) }
        }
        SettingRow {
            visible: NightLight.due
            icon: "eye"; label: "Pause until the schedule changes"
            Toggle { checked: NightLight.snoozed; onToggled: v => NightLight.snoozed = v }
        }
    }
}
