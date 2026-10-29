import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import "../../Common/Sun.js" as Sun

// Settings: one window for the whole desktop, a page per area. The pages
// list below is the navigation and the search index; a page is a
// SettingsPage file in this folder. Some entries open a page at a section
// (Wallpaper is part of Appearance); "page#section" opens any marked section.
// Shell.openSettings(id) opens it from anywhere; IPC: settings open <id>.
Scope {
    id: root

    readonly property var pages: [
        { "id": "appearance", "title": "Appearance", "icon": "palette", "group": "Look", "page": "appearance", "keys": "mode dark light ink theme color sunset" },
        { "id": "wallpaper", "title": "Wallpaper", "icon": "image", "group": "Look", "page": "appearance", "anchor": "wallpaper", "keys": "plate collection art background moving dither moonlit" },
        { "id": "motion", "title": "Motion", "icon": "sparkle", "group": "Look", "page": "appearance", "anchor": "motion", "keys": "animation reduce still gentle" },
        { "id": "lock", "title": "Lock & screensaver", "icon": "lock", "group": "Look", "page": "appearance", "anchor": "lock", "keys": "idle hibernate screensaver timeout" },
        { "id": "desktop", "title": "Desktop & dock", "icon": "grid", "group": "Look", "page": "appearance", "anchor": "desktop", "keys": "dock sidebar island icons login" },
        { "id": "displays", "title": "Displays", "icon": "display", "group": "System", "page": "displays", "keys": "monitor screen resolution refresh scale rotation arrange layout night light external" },
        { "id": "sound", "title": "Sound", "icon": "speaker", "group": "System", "page": "sound", "keys": "audio volume output input microphone speakers headphones mixer" },
        { "id": "network", "title": "Network", "icon": "wifi", "group": "System", "page": "network", "keys": "wifi wi-fi wireless ethernet wired vpn tailscale internet ip dns" },
        { "id": "bluetooth", "title": "Bluetooth", "icon": "bluetooth", "group": "System", "page": "bluetooth", "keys": "devices pair headphones airpods mouse keyboard" },
        { "id": "power", "title": "Power & battery", "icon": "battery", "group": "System", "page": "power", "keys": "battery charge profile performance saver lid health" },
        { "id": "keyboard", "title": "Keyboard", "icon": "keyboard", "group": "System", "page": "keyboard", "keys": "layout language repeat shortcuts keybinds input" },
        { "id": "pointer", "title": "Mouse & touchpad", "icon": "mouse", "group": "System", "page": "pointer", "keys": "trackpad touchpad tap scroll natural speed cursor size" },
        { "id": "notifications", "title": "Notifications", "icon": "bell", "group": "System", "page": "notifications", "keys": "focus do not disturb banners alerts apps" },
        { "id": "accessibility", "title": "Accessibility", "icon": "eye", "group": "System", "page": "accessibility", "keys": "text size larger font contrast invert colors reduce motion vision" },
        { "id": "apps", "title": "Default apps", "icon": "apps", "group": "System", "page": "apps", "keys": "browser mail files terminal open with associations startup" },
        { "id": "storage", "title": "Storage & drives", "icon": "drive", "group": "System", "page": "storage", "keys": "disk space usb removable eject mount" },
        { "id": "about", "title": "About", "icon": "info", "group": "System", "page": "about", "keys": "system version nixos hardware device name memory processor" }
    ]
    function entry(id) { return pages.find(p => p.id === id) || pages[0]; }

    // Sunset mode runs whether Settings is open or not.
    readonly property var place: Settings.get("weather.place") || ["Campana", -34.16, -58.96]
    function applySun() {
        const want = Sun.isNight(new Date(), place[1], place[2]) ? "dark" : "light";
        if (want !== Theme.mode) Theming.set({ "mode": want }, want + " mode");
    }
    Timer { interval: 60000; repeat: true; running: Settings.get("mode.auto") === true; triggeredOnStart: true; onTriggered: root.applySun() }

    IpcHandler {
        target: "settings"
        function toggle(): void { Shell.toggleSettings(""); }
        function open(page: string): void { Shell.openSettings(page); }
        function close(): void { Shell.closeAll(); }
        function current(): string { return Shell.settingsOpen ? (Shell.settingsPage || "appearance") : ""; }
        // The commands pages would have run (harness only), newest last.
        function dryrun(): string { return Sys.log.map(c => c.join(" ")).join("\n"); }
    }
    // The name the keybinds and older scripts use.
    IpcHandler {
        target: "appearance"
        function toggle(): void { Shell.toggleSettings("appearance"); }
        function open(section: string): void { Shell.openSettings(section || "appearance"); }
        function close(): void { Shell.closeAll(); }
        // Tests: choose mode, ink, collection or art as a click would.
        function look(key: string, value: string): string { const p = {}; p[key] = key === "art" ? +value : value; Theming.set(p, value); return JSON.stringify({ "busy": Theming.busy, "pending": Theme.pending, "log": Sys.log.length }); }
    }

    LazyLoader {
        active: Shell.settingsOpen
        FloatingWindow {
            id: win
            title: "Settings"
            implicitWidth: 1120
            implicitHeight: 780
            color: Theme.paper
            onVisibleChanged: if (!visible) Shell.settingsOpen = false
            Behavior on color { ColorAnimation { duration: Theme.tPage } }

            // "displays#night" opens Displays at its Night light section.
            readonly property var current: {
                const parts = (Shell.settingsPage || "appearance").split("#");
                const e = root.entry(parts[0]);
                return parts[1] ? Object.assign({}, e, { "anchor": parts[1] }) : e;
            }
            property string query: ""
            readonly property var shown: {
                const q = query.trim().toLowerCase();
                if (!q) return root.pages;
                return root.pages.filter(p => (p.title + " " + p.keys).toLowerCase().indexOf(q) >= 0);
            }
            function go(id) { Shell.settingsPage = id; }

            readonly property var components: ({
                "appearance": appearanceC, "displays": displaysC, "sound": soundC, "network": networkC, "bluetooth": bluetoothC,
                "power": powerC, "keyboard": keyboardC, "pointer": pointerC, "notifications": notificationsC, "apps": appsC,
                "storage": storageC, "about": aboutC, "accessibility": accessibilityC
            })
            Component { id: appearanceC; AppearancePage {} }
            Component { id: displaysC; DisplaysPage {} }
            Component { id: soundC; SoundPage {} }
            Component { id: networkC; NetworkPage {} }
            Component { id: bluetoothC; BluetoothPage {} }
            Component { id: powerC; PowerPage {} }
            Component { id: keyboardC; KeyboardPage {} }
            Component { id: pointerC; PointerPage {} }
            Component { id: notificationsC; NotificationsPage {} }
            Component { id: appsC; AppsPage {} }
            Component { id: storageC; StoragePage {} }
            Component { id: aboutC; AboutPage {} }
            Component { id: accessibilityC; AccessibilityPage {} }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // Navigation: search, then the pages in two groups.
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 256
                    color: Theme.mix(Theme.paper, Theme.ink, 0.05)
                    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.rule }
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 12; spacing: 8
                        RowLayout {
                            Layout.fillWidth: true; Layout.bottomMargin: 2; spacing: 10
                            Rectangle { Layout.preferredWidth: 40; Layout.preferredHeight: 40; radius: 20; color: Theme.ink
                                Text { anchors.centerIn: parent; text: (Quickshell.env("USER") || "M").charAt(0).toUpperCase(); font.family: Theme.hero; font.pixelSize: 24; color: Theme.inkText } }
                            ColumnLayout { spacing: 0; Layout.fillWidth: true; Layout.minimumWidth: 0
                                Label { text: "Settings"; font.weight: Font.DemiBold; Layout.fillWidth: true }
                                Label { text: Theme.selection.collectionName ? Theme.selection.collectionName + " · " + Theme.inkName : "Folio"; color: Theme.text2; font.pixelSize: Theme.fsS; Layout.fillWidth: true } }
                        }
                        Field {
                            id: search
                            Layout.fillWidth: true
                            icon: "search"
                            placeholder: "Search settings"
                            onTextChanged: win.query = text
                            onAccepted: if (win.shown.length) { win.go(win.shown[0].id); text = ""; }
                            onCancelled: text = ""
                        }
                        Flickable {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            contentHeight: nav.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ColumnLayout {
                                id: nav
                                width: parent.width
                                spacing: 2
                                Repeater {
                                    model: win.shown
                                    ColumnLayout {
                                        id: item
                                        required property var modelData
                                        required property int index
                                        readonly property bool first: index === 0 || win.shown[index - 1].group !== modelData.group
                                        readonly property bool on: win.current.id === modelData.id
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Cap { visible: item.first && win.query === ""; text: item.modelData.group; Layout.leftMargin: 10; Layout.topMargin: item.index ? 12 : 2; Layout.bottomMargin: 2 }
                                        Rectangle {
                                            Layout.fillWidth: true; Layout.preferredHeight: 34; radius: 9
                                            color: item.on ? Theme.ink : (hover.containsMouse ? Theme.well : "transparent")
                                            RowLayout {
                                                anchors.fill: parent; anchors.leftMargin: 7; spacing: 10
                                                Rectangle { Layout.preferredWidth: 24; Layout.preferredHeight: 24; radius: Theme.inner(9, 5)
                                                    color: item.on ? Theme.rgba(Theme.inkText, 0.22) : Theme.rgba(Theme.ink, 0.14)
                                                    Icon { anchors.centerIn: parent; name: item.modelData.icon; size: 15; color: item.on ? Theme.inkText : Theme.ink } }
                                                Label { text: item.modelData.title; color: item.on ? Theme.inkText : Theme.text; Layout.fillWidth: true; Layout.minimumWidth: 0 }
                                            }
                                            MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.go(item.modelData.id) }
                                        }
                                    }
                                }
                                Label { visible: win.shown.length === 0; text: "Nothing matches “" + win.query + "”."; color: Theme.text2; font.pixelSize: Theme.fsS; Layout.leftMargin: 10; Layout.topMargin: 8; Layout.fillWidth: true }
                            }
                        }
                        Cap { text: "Folio · " + Art.plates.length + " plates"; Layout.fillWidth: true; Layout.leftMargin: 8 }
                    }
                }

                // The page: a new page prints in; a section of the same page scrolls to it.
                Item {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Loader {
                        id: pageLoader
                        anchors.fill: parent
                        property string pageId: win.current.page
                        sourceComponent: win.components[pageId] || null
                        onLoaded: { arrive.restart(); Qt.callLater(() => { if (item && win.current.anchor) item.scrollTo(win.current.anchor); }); }
                        opacity: 0
                        SequentialAnimation {
                            id: arrive
                            PropertyAction { target: pageLoader; property: "opacity"; value: 0 }
                            PropertyAction { target: shift; property: "y"; value: 10 }
                            ParallelAnimation {
                                NumberAnimation { target: pageLoader; property: "opacity"; to: 1; duration: Theme.tQuick; easing.type: Easing.OutCubic }
                                NumberAnimation { target: shift; property: "y"; to: 0; duration: Theme.tPanel; easing.type: Easing.OutCubic }
                            }
                        }
                        transform: Translate { id: shift }
                    }
                    Connections {
                        target: win
                        function onCurrentChanged() {
                            if (pageLoader.pageId === win.current.page && pageLoader.item) pageLoader.item.scrollTo(win.current.anchor || "");
                        }
                    }
                }
            }
            // Escape in a text field is the field's (cancel, then let go of
            // the caret); otherwise it clears the search, then closes.
            Item { id: focusProbe; readonly property Item item: Window.activeFocusItem }
            Shortcut {
                sequence: "Escape"
                enabled: !(focusProbe.item && "echoMode" in focusProbe.item && focusProbe.item !== search.input)
                onActivated: { if (search.text) search.text = ""; else Shell.closeAll(); }
            }
            Shortcut { sequence: "Ctrl+F"; onActivated: search.focusNow() }
        }
    }
}
