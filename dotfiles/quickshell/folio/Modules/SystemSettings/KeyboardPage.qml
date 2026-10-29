import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets

// Keyboard: the layouts you type with and how to switch them, key repeat,
// and every shortcut niri listens for (read from its config, not editable
// here). Changes go to Folio's niri include through Services/Input, which
// checks them with niri before writing.
SettingsPage {
    id: page
    title: "Keyboard"
    description: "The layouts you type with, how keys repeat, and the shortcuts niri listens for. Changes apply at once."

    Component.onCompleted: Input.refresh()
    Connections {
        target: Input
        function onRequest(what, arg) {
            if (what === "scroll") page.scrollTo(arg);
            else if (what === "search") { shortcutSearch.text = arg; page.scrollTo("shortcuts"); }
            else if (what === "picker") { picker.open = arg !== "close"; if (picker.open) picker.query = arg === "open" ? "" : arg; }
            else if (what === "switch") switchRow.open = arg !== "close";
            else if (what === "group") page.expanded = Object.assign({}, page.expanded, { [arg]: !page.expanded[arg] });
        }
    }

    // ------------------------------------------------------------ helpers

    readonly property var layouts: Input.layouts
    readonly property bool full: layouts.length >= Input.maxLayouts
    readonly property string currentName: Input.currentLayout >= 0 && Input.currentLayout < layouts.length ? layouts[Input.currentLayout].name : ""
    function errorIn(area) { return Input.error !== "" && Input.errorArea === area; }
    // xkb names keys the X11 way ("Win"); Folio says Super.
    function keyName(s) { return String(s).replace(/\bWin\b/g, "Super").replace(/\(while pressed\)/, "(hold)"); }
    // A layout switch that is also a niri shortcut never reaches xkb.
    function takenBy(option) {
        const keys = { "grp:win_space_toggle": ["super+space", "mod+space"], "grp:alt_space_toggle": ["alt+space"], "grp:ctrl_space_toggle": ["ctrl+space"] }[option] || [];
        const hit = Input.shortcuts.find(s => keys.indexOf(s.id) >= 0);
        return hit ? hit.title : "";
    }
    readonly property var switchOptions: {
        const ids = ["grp:win_space_toggle", "grp:alt_shift_toggle", "grp:ctrl_shift_toggle", "grp:shift_caps_toggle", "grp:caps_toggle",
                     "grp:shifts_toggle", "grp:alt_space_toggle", "grp:ctrl_space_toggle", "grp:toggle", "grp:menu_toggle"];
        if (Input.switchOption && ids.indexOf(Input.switchOption) < 0) ids.push(Input.switchOption);
        const opts = [{ "value": "", "label": "No shortcut", "note": "" }];
        for (const id of ids) {
            const t = takenBy(id);
            opts.push({ "value": id, "label": keyName(Input.optionName(id)), "note": t ? "Also opens " + t : "" });
        }
        return opts;
    }
    readonly property var composeOptions: {
        const ids = ["compose:ralt", "compose:rctrl", "compose:menu", "compose:caps", "compose:rwin", "compose:prsc", "compose:sclk"];
        if (Input.composeOption && ids.indexOf(Input.composeOption) < 0) ids.push(Input.composeOption);
        return [{ "value": "", "label": "None", "note": "" }].concat(ids.map(id => ({ "value": id, "label": keyName(Input.optionName(id)), "note": "" })));
    }

    // Shortcuts: filtered by the search, grouped, each group showing a few until opened.
    property var expanded: ({})
    readonly property int preview: 6
    readonly property var found: {
        const q = shortcutSearch.text.trim().toLowerCase();
        return q ? Input.shortcuts.filter(s => q.split(/\s+/).every(w => s.search.indexOf(w) >= 0)) : Input.shortcuts;
    }
    readonly property var grouped: {
        const by = {};
        for (const s of found) (by[s.group] = by[s.group] || []).push(s);
        return Input.groups.filter(g => by[g]).map(g => ({ "name": g, "items": by[g] }));
    }

    // ------------------------------------------------------------ input sources

    Notice {
        visible: !Input.included && Input.fixture === ""
        Layout.topMargin: 12
        icon: "info"
        text: "niri does not read Folio's keyboard and pointer file yet. Changes are saved, and apply once config.kdl has include optional=true \"folio-input.kdl\"."
    }

    Section {
        title: "Input sources"
        hint: Input.keymapSource === "default" ? "None chosen, so niri types in English (US). Add the layouts you use."
              : (page.currentName ? "Typing in " + page.currentName + ". " : "")
                + (Input.keymapSource === "system" ? "From the system keymap until you change something here."
                   : "The first is the default; switch with the shortcut below.")
        Component.onCompleted: page.mark("layouts", this)
    }
    Notice { visible: page.errorIn("layouts"); icon: "info"; text: Input.error; action: "Dismiss"; onActed: Input.dismissError(); Layout.bottomMargin: 8 }
    Card {
        divided: true
        Repeater {
            model: page.layouts
            ListRow {
                id: lrow
                required property var modelData
                required property int index
                readonly property bool unused: index >= Input.maxLayouts
                icon: "keyboard"
                title: modelData.name
                subtitle: [modelData.layout + (modelData.variant ? " · " + modelData.variant : ""),
                           modelData.implicit ? "niri's default" : (index === 0 ? "Default" : ""),
                           unused ? "Not used: xkb holds four layouts" : "",
                           index === Input.currentLayout ? "In use now" : ""].filter(s => s).join(" · ")
                selected: index === Input.currentLayout
                dim: unused
                clickable: !modelData.implicit && index !== Input.currentLayout && !unused
                onClicked: Input.switchTo(index)
                Row {
                    spacing: 2
                    visible: !lrow.modelData.implicit
                    InputIconButton { icon: "down"; turn: 180; label: "Move up"; enabled: lrow.index > 0; onClicked: Input.moveLayout(lrow.index, -1) }
                    InputIconButton { icon: "down"; label: "Move down"; enabled: lrow.index < page.layouts.length - 1; onClicked: Input.moveLayout(lrow.index, 1) }
                    InputIconButton { icon: "minus"; label: "Remove"; enabled: page.layouts.length > 1; onClicked: Input.removeLayout(lrow.index) }
                }
            }
        }
        ListRow {
            icon: "plus"
            title: picker.open ? "Choose a layout to add" : "Add a layout…"
            subtitle: page.full ? "xkb holds four layouts at once; remove one to add another." : (Input.catalog.layouts.length ? "" : "Reading xkb's layouts…")
            dim: page.full
            clickable: !page.full && Input.catalog.layouts.length > 0
            onClicked: picker.open = !picker.open
        }
        InputLayoutPicker {
            id: picker
            onPicked: id => { if (Input.addLayout(id)) open = false; }
        }
    }

    Card {
        Layout.topMargin: 10
        InputSelectRow {
            id: switchRow
            icon: "globe"
            label: "Switch layouts with"
            hint: page.layouts.length < 2 ? "Add a second layout to switch between them." : (page.takenBy(Input.switchOption) ? "niri takes these keys first: " + page.takenBy(Input.switchOption) + "." : "Press it to go to the next layout.")
            options: page.switchOptions
            value: Input.switchOption
            onChosen: v => Input.setOption("grp", v)
        }
        SettingRow {
            icon: "grid"; label: "Remember the layout"
            hint: Input.trackLayout === "window" ? "Each window keeps the layout you last used in it." : "One layout for every window."
            Choice {
                options: [{ "value": "global", "label": "For all windows" }, { "value": "window", "label": "Per window" }]
                value: Input.trackLayout
                onChosen: v => Input.setKeyboard("track-layout", v)
            }
        }
        InputSelectRow {
            icon: "pencil"
            label: "Compose key"
            hint: Input.composeOption ? "Press it, then two keys: ' and e make é, o and c make ©." : "Type accents and symbols as sequences of keys."
            options: page.composeOptions
            value: Input.composeOption
            onChosen: v => Input.setOption("compose", v)
        }
    }

    // ------------------------------------------------------------ typing

    Section { title: "Typing"; hint: "How a held key repeats. Try it in the field below."; Component.onCompleted: page.mark("typing", this) }
    Notice { visible: page.errorIn("typing"); icon: "info"; text: Input.error; action: "Dismiss"; onActed: Input.dismissError(); Layout.bottomMargin: 8 }
    Card {
        divided: true
        SettingRow {
            icon: "reload"; label: "Delay before repeating"; hint: Input.repeatDelay + " ms"
            InputScale {
                low: "Short"; high: "Long"
                value: (Input.repeatDelay - 150) / 850
                onMoved: v => Input.setKeyboard("repeat-delay", Math.round((150 + v * 850) / 10) * 10)
            }
        }
        SettingRow {
            icon: "bolt"; label: "Repeat rate"; hint: Input.repeatRate + " characters a second"
            InputScale {
                low: "Slow"; high: "Fast"
                value: (Input.repeatRate - 10) / 70
                onMoved: v => Input.setKeyboard("repeat-rate", Math.round(10 + v * 70))
            }
        }
        Item {
            Layout.fillWidth: true
            implicitHeight: 58
            Field {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 14 }
                icon: "keyboard"
                placeholder: "Hold a key here to try the repeat"
            }
        }
        SettingRow {
            icon: "lock"; label: "Num Lock on at start"; hint: "Turns Num Lock on when niri starts."
            Toggle { checked: Input.numlock; onToggled: v => Input.setKeyboard("numlock", v) }
        }
    }

    // ------------------------------------------------------------ shortcuts

    Section {
        title: "Shortcuts"
        hint: Input.shortcuts.length === 0 ? "The keys niri listens for, read from its config."
              : Input.shortcuts.length + " shortcuts from niri's config (" + Input.config.files.length + (Input.config.files.length === 1 ? " file" : " files") + "). Change them there; this list follows."
        Component.onCompleted: page.mark("shortcuts", this)
    }
    Field {
        id: shortcutSearch
        Layout.fillWidth: true
        visible: Input.shortcuts.length > 0
        icon: "search"
        placeholder: "Search shortcuts by name, key or action"
        onCancelled: text = ""
    }
    Notice {
        visible: Input.shortcuts.length === 0
        icon: "keyboard"
        text: Input.config.files.length ? "niri's config sets no shortcuts." : "niri's config could not be read, so its shortcuts are not shown."
    }
    Notice {
        visible: Input.shortcuts.length > 0 && page.found.length === 0
        Layout.topMargin: 10
        icon: "search"
        text: "No shortcut matches “" + shortcutSearch.text.trim() + "”."
    }
    Repeater {
        model: page.grouped
        ColumnLayout {
            id: group
            required property var modelData
            readonly property bool searching: shortcutSearch.text.trim() !== ""
            readonly property bool all: searching || !!page.expanded[modelData.name] || modelData.items.length <= page.preview + 1
            Layout.fillWidth: true
            Layout.topMargin: 16
            spacing: 6
            RowLayout {
                Layout.fillWidth: true; Layout.leftMargin: 4; Layout.rightMargin: 4
                Cap { text: group.modelData.name; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                Cap { text: group.modelData.items.length > 99 ? "99+" : String(group.modelData.items.length) }
            }
            Card {
                divided: true
                Repeater {
                    model: group.all ? group.modelData.items : group.modelData.items.slice(0, page.preview)
                    InputShortcutRow {
                        required property var modelData
                        title: modelData.title
                        detail: modelData.detail + (modelData.src ? "  ·  " + modelData.src : "")
                        caps: modelData.caps
                    }
                }
                ListRow {
                    visible: !group.searching && group.modelData.items.length > page.preview + 1
                    icon: ""
                    implicitHeight: 40
                    title: page.expanded[group.modelData.name] ? "Show fewer" : "Show all " + group.modelData.items.length
                    onClicked: page.expanded = Object.assign({}, page.expanded, { [group.modelData.name]: !page.expanded[group.modelData.name] })
                }
            }
        }
    }
}
