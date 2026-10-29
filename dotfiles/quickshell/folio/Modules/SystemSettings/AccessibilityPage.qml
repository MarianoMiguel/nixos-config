import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// Accessibility: text size, contrast, inverted colors and motion, the parts
// of a mature desktop's accessibility settings that Folio and niri can do.
// Text size reaches GTK apps through text-scaling-factor; inverted colors go
// through the same gamma relay as Night light.
SettingsPage {
    id: page
    title: "Accessibility"
    description: "Make the desktop easier to see and calmer to use. Changes apply at once."

    function textScale(v) {
        Settings.set("text.scale", v);
        Sys.run(["gsettings", "set", "org.gnome.desktop.interface", "text-scaling-factor", String(v)]);
    }

    // A sample of what the settings below do.
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 12
        implicitHeight: sample.implicitHeight + 36
        radius: Theme.rL
        color: Theme.wash
        border.color: Theme.rule
        Sheet {
            id: sheet
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            height: sample.implicitHeight
            radius: Theme.rM
            elevation: 0.4
            ColumnLayout {
                id: sample
                width: parent.width
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true; Layout.margins: 14; spacing: 12
                    Rectangle { Layout.preferredWidth: 34; Layout.preferredHeight: 34; radius: Theme.rS; color: Theme.ink
                        Icon { anchors.centerIn: parent; name: "message"; size: 18; color: Theme.inkText } }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                        Label { text: "Lunch on Friday?"; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        Text { text: "The place by the river opens at noon. I can book a table for four if you are in."
                               color: Theme.text2; font.family: Theme.ui; font.pixelSize: Theme.fsS; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        Cap { text: "Messages · 12:40"; Layout.topMargin: 2 }
                    }
                }
            }
        }
    }

    Section { title: "Seeing" }
    Card {
        divided: true
        SettingRow {
            icon: "note"; label: "Text size"; hint: "Folio and GTK apps; other apps follow their own settings."
            Choice {
                options: [{ "value": 1, "label": "Default" }, { "value": 1.12, "label": "Larger" }, { "value": 1.25, "label": "Large" }, { "value": 1.5, "label": "Largest" }]
                value: [1, 1.12, 1.25, 1.5].find(v => Math.abs(v - Theme.textScale) < 0.01) || 1
                onChosen: v => page.textScale(v)
            }
        }
        SettingRow {
            icon: "eye"; label: "Higher contrast"; hint: "Firmer text and edges; panels let less of the plate through."
            Toggle { checked: Theme.high; onToggled: v => Settings.set("contrast", v ? "high" : "normal") }
        }
        SettingRow {
            icon: "sparkle"; label: "Invert colors"; hint: "The whole screen, light for dark."
            Toggle { checked: NightLight.invert; onToggled: v => Settings.set("colors.invert", v) }
        }
        SettingRow {
            icon: "moon"; label: "Night light"; hint: NightLight.schedule === "off" ? "Off." : (NightLight.active ? "On now." : "Scheduled.")
            Button { text: "Displays"; icon: "right"; onClicked: Shell.openSettings("displays#night") }
        }
    }

    Section { title: "Motion" }
    Card {
        divided: true
        SettingRow {
            icon: "sparkle"; label: "Reduce motion"; hint: "Changes cut instead of moving; plates appear whole."
            Toggle { checked: Settings.get("motion") === "still"; onToggled: v => Settings.set("motion", v ? "still" : "full") }
        }
        SettingRow {
            icon: "image"; label: "Moving dither"; hint: "The plate keeps re-printing itself. Plugged in: it holds still on battery, which also spares the blur behind panels."
            Choice {
                options: [{ "value": "always", "label": "Always" }, { "value": "plugged", "label": "Plugged in" }, { "value": "off", "label": "Off" }]
                value: !(Settings.get("plates.breathe") > 0) ? "off" : Settings.get("plates.breatheOnBattery") === true ? "always" : "plugged"
                onChosen: v => { Settings.set("plates.breathe", v === "off" ? 0 : 1); Settings.set("plates.breatheOnBattery", v === "always"); }
            }
        }
    }

    Section { title: "Pointing and typing" }
    Card {
        divided: true
        ListRow {
            icon: "mouse"; title: "Mouse & touchpad"; subtitle: "Pointer speed, tap to click, scrolling."
            onClicked: Shell.openSettings("pointer")
            Icon { name: "right"; size: 16; color: Theme.text3 }
        }
        ListRow {
            icon: "keyboard"; title: "Keyboard"; subtitle: "Repeat speed, layouts and shortcuts."
            onClicked: Shell.openSettings("keyboard")
            Icon { name: "right"; size: 16; color: Theme.text3 }
        }
    }
}
