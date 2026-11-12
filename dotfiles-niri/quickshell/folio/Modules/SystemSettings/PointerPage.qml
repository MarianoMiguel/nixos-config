import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// Mouse & touchpad: how the pointer moves, clicks and scrolls, per kind of
// device. A section shows only for devices this machine has (a laptop always
// keeps its touchpad). Changes go to Folio's niri include through
// Services/Input, which writes each device's section complete.
SettingsPage {
    id: page
    title: "Mouse & touchpad"
    description: "How the pointer moves, clicks and scrolls. Changes apply at once."

    Component.onCompleted: Input.refresh()
    Connections {
        target: Input
        function onRequest(what, arg) { if (what === "scroll") page.scrollTo(arg); }
    }

    readonly property var pad: Input.touchpad
    readonly property var mouse: Input.mouse
    readonly property var stick: Input.trackpoint
    readonly property bool anything: Input.hasTouchpad || Input.hasMouse || Input.hasTrackpoint
    function errorIn(area) { return Input.error !== "" && Input.errorArea === area; }
    // accel-speed runs -1..1; the slider 0..2, so its middle mark is the default.
    function speed(v) { return (typeof v === "number" ? v : 0) + 1; }
    function names(list) { return list.length ? list.join(", ") : ""; }
    function speedHint(v) { const x = typeof v === "number" ? v : 0; return Math.abs(x) < 0.01 ? "Default" : (x > 0 ? "Faster than default" : "Slower than default"); }

    Notice {
        visible: !Input.included && Input.fixture === ""
        Layout.topMargin: 12
        icon: "info"
        text: "niri does not read Interstellar's keyboard and pointer file yet. Changes are saved, and apply once config.kdl has include optional=true \"folio-input.kdl\"."
    }
    Notice {
        visible: !page.anything
        Layout.topMargin: 16
        icon: "mouse"
        text: "No mouse or touchpad found. Their settings appear here when one is connected."
    }

    // ------------------------------------------------------------ general

    Section { visible: page.anything; title: "Buttons"; Component.onCompleted: page.mark("general", this) }
    Notice { visible: page.errorIn("general"); icon: "info"; text: Input.error; action: "Dismiss"; onActed: Input.dismissError(); Layout.bottomMargin: 8 }
    Card {
        visible: page.anything
        SettingRow {
            icon: "mouse"; label: "Primary button"
            hint: Input.leftHanded ? "The right button clicks; the left opens menus." : "The left button clicks; the right opens menus."
            Choice {
                options: [{ "value": false, "label": "Left" }, { "value": true, "label": "Right" }]
                value: Input.leftHanded
                onChosen: v => Input.setPrimary(v)
            }
        }
    }

    // ------------------------------------------------------------ touchpad

    Section {
        visible: Input.hasTouchpad
        title: "Touchpad"
        hint: page.names(Input.hardware.touchpads) || "This laptop's touchpad."
        Component.onCompleted: page.mark("touchpad", this)
    }
    Notice { visible: page.errorIn("touchpad"); icon: "info"; text: Input.error; action: "Dismiss"; onActed: Input.dismissError(); Layout.bottomMargin: 8 }
    Card {
        visible: Input.hasTouchpad
        divided: true
        SettingRow {
            icon: "touchpad"; label: "Tap to click"; hint: "A light tap clicks; two fingers right-click."
            Toggle { checked: !!page.pad.tap; onToggled: v => Input.setDevice("touchpad", "tap", v) }
        }
        SettingRow {
            icon: "arrow"; label: "Tap and drag"; hint: page.pad.tap ? "Tap, then tap again and slide to drag." : "Needs tap to click."
            opacity: page.pad.tap ? 1 : 0.5
            enabled: !!page.pad.tap
            Behavior on opacity { NumberAnimation { duration: Theme.tQuick } }
            Toggle { checked: !!page.pad.tap && page.pad.drag !== false; onToggled: v => Input.setDevice("touchpad", "drag", v) }
        }
        SettingRow {
            icon: "down"; label: "Natural scrolling"; hint: page.pad["natural-scroll"] ? "Content moves with your fingers." : "Content moves against your fingers, like a scroll bar."
            Toggle { checked: !!page.pad["natural-scroll"]; onToggled: v => Input.setDevice("touchpad", "natural-scroll", v) }
        }
        SettingRow {
            icon: "bolt"; label: "Pointer speed"; hint: page.speedHint(page.pad["accel-speed"])
            InputScale {
                low: "Slow"; high: "Fast"; to: 2; step: 0.1
                value: page.speed(page.pad["accel-speed"])
                onMoved: v => Input.setDevice("touchpad", "accel-speed", Math.round((v - 1) * 100) / 100)
            }
        }
        SettingRow {
            icon: "keyboard"; label: "Ignore while typing"; hint: "Stops a palm from moving the pointer."
            Toggle { checked: !!page.pad.dwt; onToggled: v => Input.setDevice("touchpad", "dwt", v) }
        }
        SettingRow {
            icon: "right"; label: "Scroll with"
            hint: page.pad["scroll-method"] === "edge" ? "One finger along the right edge." : "Two fingers anywhere."
            Choice {
                options: [{ "value": "two-finger", "label": "Two fingers" }, { "value": "edge", "label": "Edge" }]
                value: page.pad["scroll-method"] === "edge" ? "edge" : "two-finger"
                onChosen: v => Input.setDevice("touchpad", "scroll-method", v)
            }
        }
        SettingRow {
            icon: "check"; label: "Click with"
            hint: page.pad["click-method"] === "clickfinger" ? "Press with one finger to click, two to right-click, three to middle-click."
                                                             : "Press the bottom right corner to right-click."
            Choice {
                options: [{ "value": "clickfinger", "label": "Fingers" }, { "value": "button-areas", "label": "Areas" }]
                value: page.pad["click-method"] === "clickfinger" ? "clickfinger" : "button-areas"
                onChosen: v => Input.setDevice("touchpad", "click-method", v)
            }
        }
        SettingRow {
            icon: "mouse"; label: "Off while a mouse is connected"
            Toggle { checked: !!page.pad["disabled-on-external-mouse"]; onToggled: v => Input.setDevice("touchpad", "disabled-on-external-mouse", v) }
        }
    }

    // ------------------------------------------------------------ mouse

    Section {
        visible: page.anything
        title: "Mouse"
        hint: Input.hasMouse ? page.names(Input.hardware.mice) : ""
        Component.onCompleted: page.mark("mouse", this)
    }
    Notice { visible: page.errorIn("mouse"); icon: "info"; text: Input.error; action: "Dismiss"; onActed: Input.dismissError(); Layout.bottomMargin: 8 }
    Notice {
        visible: page.anything && !Input.hasMouse
        icon: "mouse"
        text: "No mouse connected. Its settings appear here when you plug one in."
    }
    Card {
        visible: Input.hasMouse
        divided: true
        SettingRow {
            icon: "bolt"; label: "Pointer speed"; hint: page.speedHint(page.mouse["accel-speed"])
            InputScale {
                low: "Slow"; high: "Fast"; to: 2; step: 0.1
                value: page.speed(page.mouse["accel-speed"])
                onMoved: v => Input.setDevice("mouse", "accel-speed", Math.round((v - 1) * 100) / 100)
            }
        }
        SettingRow {
            icon: "sparkle"; label: "Acceleration"
            hint: page.mouse["accel-profile"] === "flat" ? "The pointer moves as far as the mouse, however fast." : "Quick movements carry the pointer further."
            Choice {
                options: [{ "value": "adaptive", "label": "Adaptive" }, { "value": "flat", "label": "Flat" }]
                value: page.mouse["accel-profile"] === "flat" ? "flat" : "adaptive"
                onChosen: v => Input.setDevice("mouse", "accel-profile", v)
            }
        }
        SettingRow {
            icon: "down"; label: "Natural scrolling"; hint: page.mouse["natural-scroll"] ? "Content moves with the wheel." : "Content moves against the wheel."
            Toggle { checked: !!page.mouse["natural-scroll"]; onToggled: v => Input.setDevice("mouse", "natural-scroll", v) }
        }
    }

    // ------------------------------------------------------------ trackpoint

    Section {
        visible: Input.hasTrackpoint
        title: "TrackPoint"
        hint: page.names(Input.hardware.trackpoints)
        Component.onCompleted: page.mark("trackpoint", this)
    }
    Notice { visible: page.errorIn("trackpoint"); icon: "info"; text: Input.error; action: "Dismiss"; onActed: Input.dismissError(); Layout.bottomMargin: 8 }
    Card {
        visible: Input.hasTrackpoint
        divided: true
        SettingRow {
            icon: "bolt"; label: "Pointer speed"; hint: page.speedHint(page.stick["accel-speed"])
            InputScale {
                low: "Slow"; high: "Fast"; to: 2; step: 0.1
                value: page.speed(page.stick["accel-speed"])
                onMoved: v => Input.setDevice("trackpoint", "accel-speed", Math.round((v - 1) * 100) / 100)
            }
        }
        SettingRow {
            icon: "sparkle"; label: "Acceleration"
            Choice {
                options: [{ "value": "adaptive", "label": "Adaptive" }, { "value": "flat", "label": "Flat" }]
                value: page.stick["accel-profile"] === "flat" ? "flat" : "adaptive"
                onChosen: v => Input.setDevice("trackpoint", "accel-profile", v)
            }
        }
    }
}
