import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// One screen's dock: 10 px from the bottom, 68 px tall, radius 24. Icons
// are 50 px and shrink when there are many, so the dock (magnified too)
// always fits. They sit 9 px in from every edge, and their tiles' corners
// are the dock's less that inset (Theme.inner), so the curves are concentric.
// Magnification is a gaussian of the pointer's distance from each icon's
// resting centre (up to 1.62 over ~105 px), eased every frame.
PanelWindow {
    id: win

    Entrance { target: win.contentItem; part: "dock"; fromY: 96 }

    property var dock
    readonly property real gap: 8
    readonly property real radius: 24
    readonly property real inset: 9                // icon to dock edge, on every side
    readonly property real pad: inset - gap / 2    // + half a gap = the inset
    // Tile corners as a share of the icon: 15 px on a 50 px icon.
    readonly property real corner: Theme.inner(radius, inset) / 50
    readonly property real sepSlot: 15             // rule 1 px, 3 px margins, a gap each side
    readonly property real maxScale: 1.62

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "folio:dock"
    // The keyboard only while the dock is asked for it (Mod+Ctrl+D).
    WlrLayershell.keyboardFocus: keyMode ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // Windows stop above the dock's band (10 px margin + 68 px), as on a Mac,
    // unless Settings says they may run under it. Magnified icons still rise
    // over windows. A zone of 0 reserves nothing.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: Settings.get("dock.reserve") !== false ? 78 : 0
    anchors { bottom: true; left: true; right: true }
    implicitHeight: 200
    color: "transparent"
    // A fullscreen window covers the dock: it slides down out of the way, as
    // it arrived, rather than vanishing, and rises again when the window
    // leaves fullscreen. A spring, so a quick toggle reverses smoothly.
    readonly property bool away: !!dock && !keyMode && (dock.fakeAway || (!!screen && Niri.fullscreenOn(screen.name, screen.width, screen.height)))
    property real awayY: away ? 110 : 0
    Behavior on awayY { SpringPanel {} }

    mask: Region { item: win.away ? null : zone }
    // Re-sent once the sheet has settled after apps come and go.
    BlurNudge { id: frost; key: Math.round(sheet.width) + (tip.opacity > 0.5 ? "t" : "") + (win.away ? "a" : "") }
    BackgroundEffect.blurRegion: Region {
        item: win.away ? null : sheet
        radius: win.radius + frost.extra
        Region { item: tip.opacity > 0.5 ? tip : null; radius: Theme.rS }
    }

    // Icon size: 50 px until the dock would not fit, magnification included.
    // Past the apps, two fixed slots: Settings and the Trash.
    readonly property int count: { let n = 0; for (let i = 0; i < apps.count; i++) if (apps.itemAt(i) && !apps.itemAt(i).leaving) n++; return n; }
    readonly property int fixed: 2
    readonly property real base: {
        const room = width - 48 - (dock.magnify ? 100 : 0) - pad * 2 - (count ? sepSlot : 0);
        return Math.max(24, Math.min(50, Math.floor(room / (count + fixed) - gap)));
    }

    readonly property string launcherIcon: Quickshell.iconPath("org.gnome.Settings", true) || Quickshell.iconPath("preferences-system", true) || Quickshell.iconPath("systemsettings", true) || ""

    // The Trash: the icon theme's empty or full can (Folio's glyph without
    // one), as Drives reads it; Drives watches it while a dock shows it.
    readonly property bool trashFull: Drives.trash.known && Drives.trash.items > 0
    readonly property string trashEmptyIcon: Quickshell.iconPath("user-trash", true) || ""
    readonly property string trashFullIcon: Quickshell.iconPath("user-trash-full", true) || ""
    Component.onCompleted: Drives.watchTrash()
    Component.onDestruction: Drives.unwatchTrash()

    // ------------------------------------------------------------ magnification

    property real pointer: -1                      // window x, -1 when away
    property bool settled: true
    property real peak: 1                          // the largest scale now
    readonly property bool held: menu.open
    onPointerChanged: settled = false
    onBaseChanged: settled = false
    onHeldChanged: settled = false

    function slots() {
        const out = [];
        for (let i = 0; i < apps.count; i++) if (apps.itemAt(i)) out.push(apps.itemAt(i));
        return out;
    }
    function step(dt) {
        const k = Theme.motion < 0.1 ? 1 : 1 - Math.pow(0.8, Math.min(4, dt * 60));
        const list = slots();
        let rest = pad * 2 + sep.restWidth + (base + gap) * fixed;
        for (const it of list) rest += (base + gap) * Math.max(0, it.appear);
        let x = (width - rest) / 2 + pad;
        const centres = [];
        for (const it of list) { const w = (base + gap) * Math.max(0, it.appear); centres.push(x + w / 2); x += w; }
        x += sep.restWidth;
        centres.push(x + (base + gap) / 2, x + (base + gap) * 1.5);
        list.push(launcher, trash);
        let still = true, top = 1;
        const px = held ? heldAt : pointer;
        for (let i = 0; i < list.length; i++) {
            const d = px - centres[i];
            const t = px < 0 || !dock.magnify ? 1 : 1 + (maxScale - 1) * Math.exp(-(d * d) / (2 * 105 * 105 * 0.45));
            let s = list[i].s + (t - list[i].s) * k;
            if (Math.abs(t - s) < 0.002) s = t; else still = false;
            list[i].s = s;
            top = Math.max(top, s);
        }
        peak = top;
        settled = still;
        placeTip();
    }
    property real heldAt: -1
    FrameAnimation {
        running: win.visible && !win.settled
        onTriggered: win.step(frameTime)
    }

    // ------------------------------------------------------------ the dock

    // Input and hover: the sheet, plus whatever the icons grew above it.
    Item {
        id: zone
        transform: Translate { y: win.awayY }
        readonly property real grow: Math.max(0, win.base * win.peak + win.inset - 68)
        width: sheet.width
        x: Math.round((win.width - width) / 2)
        height: 68 + grow
        y: win.height - 10 - height

        HoverHandler {
            id: hover
            onPointChanged: win.pointer = hovered ? zone.x + point.position.x : -1
            onHoveredChanged: win.pointer = hovered ? zone.x + point.position.x : -1
        }
        // Pointer use here hides focus rings elsewhere in Folio.
        PointerWatch { }

        Sheet {
            id: sheet
            anchors.bottom: parent.bottom
            width: win.pad * 2 + row.width
            height: 68
            radius: win.radius
        }

        Row {
            id: row
            x: win.pad
            y: zone.height - win.inset - win.base
            height: win.base

            Repeater {
                id: apps
                model: win.dock.model
                DockItem {
                    id: slotItem
                    required property var model
                    keyFocus: win.keyItem !== null && win.keyItem === slotItem
                    corner: win.corner
                    key: model.key
                    appId: model.appId
                    name: model.name
                    icon: model.icon
                    pinned: model.pinned
                    running: model.running
                    leaving: model.leaving
                    fresh: model.fresh
                    base: win.base
                    gap: win.gap
                    mode: win.dock.iconMode
                    shape: win.dock.shapes[icon] || ""
                    probe: win.learn
                    onGone: win.dock.removeKey(key)
                    onActivated: (button, at) => win.activate(this, button, at)
                    onHoveredChanged: win.hoverChanged(this)
                    onSChanged: if (win.tipFor === this) win.placeTip()
                }
            }

            // The rule between the apps and Settings.
            Item {
                id: sep
                readonly property real restWidth: win.count > 0 ? win.sepSlot : 0
                width: restWidth
                height: win.base
                Behavior on width { SpringSoft {} }
                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: win.base * 0.76
                    color: Theme.ruleStrong
                    opacity: win.count > 0 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.tQuick } }
                }
            }

            DockItem {
                id: launcher
                keyFocus: win.keyItem !== null && win.keyItem === launcher
                corner: win.corner
                key: "folio:settings"
                name: "Settings"
                icon: win.launcherIcon
                glyph: "gear"
                base: win.base
                gap: win.gap
                mode: win.dock.iconMode
                shape: win.dock.shapes[icon] || ""
                probe: win.learn
                onActivated: (button, at) => {
                    if (button === Qt.RightButton) return;
                    stamp();
                    if (!win.dock.fx) Shell.openSettings("");
                }
                onHoveredChanged: win.hoverChanged(this)
            }

            // The Trash, at the end: a click opens it in Files, the right
            // button its menu (Open, Empty Trash).
            DockItem {
                id: trash
                keyFocus: win.keyItem !== null && win.keyItem === trash
                corner: win.corner
                key: "folio:trash"
                name: "Trash"
                icon: win.trashFull ? (win.trashFullIcon || win.trashEmptyIcon) : win.trashEmptyIcon
                glyph: "trash"
                base: win.base
                gap: win.gap
                mode: win.dock.iconMode
                shape: win.dock.shapes[icon] || ""
                probe: win.learn
                onActivated: (button, at) => win.activateTrash(button, at, false)
                onHoveredChanged: win.hoverChanged(this)
            }
        }
    }

    // ------------------------------------------------------------ tooltip

    property var tipFor: null
    function hoverChanged(it) {
        if (it.hovered) tipFor = it;
        else if (tipFor === it) tipFor = keyItem;
        placeTip();
    }
    function placeTip() {
        if (!tipFor) return;
        const p = tipFor.mapToItem(win.contentItem, tipFor.width / 2, tipFor.height - tipFor.size - tipFor.hop);
        tip.cx = p.x;
        tip.ty = p.y;
    }
    Item {
        id: tip
        property real cx: 0
        property real ty: 0
        // Toasts rest where the tooltip would print; while one is up, it wins.
        readonly property bool shown: win.tipFor !== null && !win.tipFor.pressed && !menu.open && Toasts.items.length === 0
        property string text: ""
        Connections { target: win; function onTipForChanged() { if (win.tipFor) tip.text = win.tipFor.name; } }
        width: Math.min(280, label.implicitWidth + 20)
        height: label.implicitHeight + 10
        x: Math.round(Math.max(8, Math.min(win.width - width - 8, cx - width / 2)))
        y: Math.round(ty - 12 - height + (shown ? 0 : 4))
        opacity: shown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.tQuick; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !tip.shown; NumberAnimation { duration: Theme.tQuick } }
        Sheet {
            anchors.fill: parent
            radius: Theme.rS
            elevation: 0.5
        }
        Cap {
            id: label
            anchors.centerIn: parent
            width: Math.min(implicitWidth, 260)
            text: tip.text
            color: Theme.text2
        }
    }

    // ------------------------------------------------------------ actions

    function activate(it, button, at) {
        if (button === Qt.RightButton) { openMenu(it, at); return; }
        it.stamp();
        if (button === Qt.MiddleButton) { if (dock.launch(it.key)) it.bounce(); return; }
        if (dock.activate(it.key) === "launch") it.bounce();
    }
    function openMenu(it, at, keyed) {
        const list = [];
        const fake = !!dock.fx;
        if (fake || dock.entries[it.key]) list.push({ "label": "New window", "run": () => { if (dock.newWindow(it.key)) it.bounce(); } });
        list.push({ "label": it.pinned ? "Unpin from dock" : "Pin to dock", "run": () => dock.setPinned(it.key, it.appId, !it.pinned) });
        if (it.running > 0) {
            list.push({ "rule": true });
            list.push({ "label": it.running > 1 ? "Close " + it.running + " windows" : "Close window", "danger": true, "run": () => dock.closeAll(it.key) });
        }
        // From the keyboard: what it chooses gives the keyboard back first,
        // so the app it opens or focuses gets it; the first item is lit.
        if (keyed) for (const x of list) if (x.run) { const run = x.run; x.run = () => { win.leaveKeys(); run(); }; }
        heldAt = pointer;
        // Above the icon, from the pointer's x. The menu covers the screen;
        // this window is its bottom band.
        const top = it.mapToItem(null, 0, it.height - it.size - it.hop).y - 4;
        menu.popup(Qt.point(at.x, top + (screen ? screen.height : height) - height), it.name + (it.running > 1 ? " · " + it.running + " windows" : ""), list);
        if (keyed) menu.step(1);
    }

    // The Trash: a click opens it in Files; its menu opens it or empties it
    // (Drives' countdown toast, which Cancel stops; never a question).
    function activateTrash(button, at, keyed) {
        if (button === Qt.RightButton) { openTrashMenu(at, keyed); return; }
        trash.stamp();
        Drives.openTrash();
    }
    readonly property string trashLine: {
        const t = Drives.trash;
        if (!t.known) return "Counting";
        if (Drives.emptying) return "Emptying";
        if (t.items === 0) return "Empty";
        // As Settings › Storage says it: "12,847 items · 48 GB".
        return Number(t.items).toLocaleString(Qt.locale("en_US"), "f", 0) + (t.items === 1 ? " item · " : " items · ") + Drives.bytes(t.size);
    }
    function openTrashMenu(at, keyed) {
        const list = [
            { "label": "Open", "run": () => { trash.stamp(); Drives.openTrash(); } },
            { "rule": true },
            { "label": "Empty Trash", "danger": true, "disabled": !trashFull || Drives.emptying, "run": () => Drives.askEmptyTrash() }
        ];
        if (keyed) for (const x of list) if (x.run) { const run = x.run; x.run = () => { win.leaveKeys(); run(); }; }
        heldAt = pointer;
        const top = trash.mapToItem(null, 0, trash.height - trash.size - trash.hop).y - 4;
        menu.popup(Qt.point(at.x, top + (screen ? screen.height : height) - height), "Trash · " + trashLine, list);
        if (keyed) menu.step(1);
    }

    // ------------------------------------------------------------ keyboard

    // Mod+Ctrl+D (dock.keyboard over IPC) hands this screen's dock the
    // keyboard: a ring marks an app and its name shows above it. Left and
    // Right move, Home and End go to the ends, Enter or Space opens it, Up,
    // Shift+F10 or the Menu key open its menu, Esc gives the keyboard back.
    // Opening an app gives it back too, and so does using the pointer
    // (a still, transparent layer over the screen notices), so keys never
    // stay with the dock once you are elsewhere.
    property bool keyMode: false
    property int cursor: 0
    property Item keyItem: null
    function keyItems() { return slots().filter(it => !it.leaving).concat([launcher, trash]); }
    function moveKey(i) {
        const list = keyItems();
        cursor = Math.max(0, Math.min(list.length - 1, i));
        keyItem = keyMode ? list[cursor] : null;
        if (keyItem) tipFor = keyItem;
        placeTip();
        dock.keyState = keyMode && keyItem ? cursor + ":" + keyItem.name : "";
    }
    function enterKeys() {
        // Start at the app that has the focused window, else the first.
        const list = keyItems();
        const i = list.findIndex(it => (dock.windowIds[it.key] || []).some(id => Niri.windows[id] && Niri.windows[id].is_focused));
        keyMode = true;
        KeyNav.key();
        keys.forceActiveFocus();
        moveKey(Math.max(0, i));
    }
    function leaveKeys() {
        if (!keyMode) return;
        keyMode = false;
        keyItem = null;
        if (tipFor && !tipFor.hovered) tipFor = null;
        dock.keyState = "";
    }
    function keyAt(it) { return it.mapToItem(null, it.width / 2, it.height - it.size - it.hop); }
    Item {
        id: keys
        focus: true
        Keys.onPressed: event => {
            if (!win.keyMode) return;
            KeyNav.key();
            const it = win.keyItem;
            const k = event.key;
            if (k === Qt.Key_Escape) win.leaveKeys();
            else if (KeyNav.opensMenu(event) || (k === Qt.Key_Up && KeyNav.plain(event))) {
                if (it === trash) win.openTrashMenu(win.keyAt(it), true);
                else if (it && it !== launcher) win.openMenu(it, win.keyAt(it), true);
            } else if (KeyNav.activates(event)) {
                if (!it || event.isAutoRepeat) { event.accepted = true; return; }
                win.leaveKeys();
                if (it === launcher) { it.stamp(); if (!win.dock.fx) Shell.openSettings(""); }
                else if (it === trash) win.activateTrash(Qt.LeftButton, win.keyAt(it), false);
                else win.activate(it, Qt.LeftButton, win.keyAt(it));
            } else if (!KeyNav.plain(event)) return;
            else if (k === Qt.Key_Left) win.moveKey(win.cursor - 1);
            else if (k === Qt.Key_Right) win.moveKey(win.cursor + 1);
            else if (k === Qt.Key_Home) win.moveKey(0);
            else if (k === Qt.Key_End) win.moveKey(1e6);
            else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) win.moveKey(win.cursor + (k === Qt.Key_Tab ? 1 : -1));
            event.accepted = true;
        }
    }
    // Apps coming and going keep the ring on a real item.
    Connections {
        target: apps
        function onCountChanged() { if (win.keyMode) Qt.callLater(() => win.moveKey(win.cursor)); }
    }
    Connections {
        target: win.dock
        function onKeysRequested() {
            if (win.screen !== Shell.screenFor(Quickshell.screens)) return;
            if (win.keyMode) win.leaveKeys(); else win.enterKeys();
        }
    }
    // While the dock has the keyboard: a still layer over the screen that
    // gives the keyboard back the moment the pointer moves or presses, so
    // keys go where you go. It sits under the app menu.
    PanelWindow {
        id: watch
        screen: win.screen
        visible: win.keyMode && !menu.open
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "folio:dock-keys"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: win.leaveKeys()
            PointerWatch { onMoved: win.leaveKeys() }
        }
    }
    // IPC presses, on the focused screen only.
    Connections {
        target: win.dock
        function onPressed(index, how) {
            if (win.screen !== Shell.screenFor(Quickshell.screens)) return;
            if (how === "close") { menu.close(); return; }
            const list = win.slots().concat([launcher, trash]);
            const it = index === -2 ? trash : list[index];
            if (!it) return;
            const at = it.mapToItem(null, it.width / 2, it.height - it.size / 2);
            // As a click would: each slot answers its own (apps, Settings, the Trash).
            it.activated(how === "menu" ? Qt.RightButton : how === "middle" ? Qt.MiddleButton : Qt.LeftButton, at);
        }
    }
    // The dock's menus appear and go at once (instant): used constantly,
    // they skip the print every other menu has.
    ContextMenu {
        id: menu
        screen: win.screen
        side: "above"
        instant: true
        maxWidth: 300
        layerName: "folio:dock-menu"
        onDismissed: { win.heldAt = -1; win.settled = false; }
        onOpenChanged: if (open) win.dock.openMenu = menu
        onChosen: (i, label) => win.dock.lastChosen = label
    }

    // ------------------------------------------------------------ icon shapes

    // Learns whether an icon ships its own tile (square) or is round or free-
    // form, from its alpha: plated and printed put only the latter on paper.
    function learn(src) { probe.add(src); }
    function classify(d) {
        const N = 32;
        const on = (x, y) => d[(y * N + x) * 4 + 3] > 128;
        let x0 = N, y0 = N, x1 = -1, y1 = -1, n = 0;
        for (let y = 0; y < N; y++)
            for (let x = 0; x < N; x++)
                if (on(x, y)) { n++; x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
        if (!n) return "free";
        const w = x1 - x0 + 1, h = y1 - y0 + 1;
        if (w < N * 0.8 || h < N * 0.8 || Math.abs(w - h) > N * 0.12) return "free";
        const ix = Math.round(w * 0.12), iy = Math.round(h * 0.12);
        const corners = [on(x0 + ix, y0 + iy), on(x1 - ix, y0 + iy), on(x0 + ix, y1 - iy), on(x1 - ix, y1 - iy)].filter(Boolean).length;
        return n / (w * h) > 0.86 && corners >= 3 ? "square" : "free";
    }
    Canvas {
        id: probe
        width: 32; height: 32
        opacity: 0
        property var queue: []
        property string current: ""
        function add(src) {
            if (src in win.dock.shapes || queue.indexOf(src) >= 0 || src === current) return;
            queue.push(src);
            next();
        }
        function next() {
            if (current || !queue.length) return;
            current = queue.shift();
            giveUp.restart();
            if (isImageLoaded(current) || isImageError(current)) requestPaint(); else loadImage(current);
        }
        function finish(shape) {
            giveUp.stop();
            win.dock.setShape(current, shape);
            current = "";
            next();
        }
        // An icon that never loads counts as free-form.
        Timer { id: giveUp; interval: 3000; onTriggered: if (probe.current) probe.finish("free") }
        onImageLoaded: if (current) requestPaint()
        onPaint: {
            const src = current;
            if (!src || !(isImageLoaded(src) || isImageError(src))) return;
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, 32, 32);
            let shape = "free";
            if (isImageLoaded(src)) {
                ctx.drawImage(src, 0, 0, 32, 32);
                shape = win.classify(ctx.getImageData(0, 0, 32, 32).data);
            }
            unloadImage(src);
            finish(shape);
        }
    }
}
