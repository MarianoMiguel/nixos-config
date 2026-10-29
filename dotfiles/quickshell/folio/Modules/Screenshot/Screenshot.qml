import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.Widgets

// The floating screenshot thumbnail. After a capture a 16:10 print of it
// slides in at the bottom right, above the dock's band, and stays 6 s (hover
// holds it). Click opens it; Copy puts it on the clipboard; Delete moves it
// aside at once and to the Trash when the undo toast times out; drag it out
// to drop the file somewhere; swipe it right to dismiss. New files in the
// screenshots folder show it, so any capture tool works.
Scope {
    id: root

    readonly property string dir: Quickshell.env("FOLIO_SCREENSHOTS_DIR") || (Quickshell.env("HOME") + "/Pictures/Screenshots")
    property string path: ""
    property bool shown: false
    property bool dry: false                // fixtures: open and trash do nothing real
    property var restoring: ({})            // paths the shell moved back itself; the watcher skips them
    readonly property string url: path ? "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F") : ""
    readonly property string title: { const n = path.slice(path.lastIndexOf("/") + 1); return n.replace(/\.[^.]+$/, ""); }
    signal shownAgain()

    function show(p, fake) {
        if (!p) return;
        path = p;
        dry = !!fake;
        shown = true;
        shownAgain();
    }
    function dismiss() { shown = false; }
    function skip(p) { const r = Object.assign({}, restoring); r[p] = Date.now(); restoring = r; }
    function open() {
        if (!dry) Quickshell.execDetached(["xdg-open", path]);
        dismiss();
    }
    function copy() { Quickshell.execDetached(["sh", "-c", "wl-copy --type image/png < \"$1\"", "sh", path]); }
    function remove() {
        const p = path, fake = dry;
        const folder = p.slice(0, p.lastIndexOf("/")) || "/";
        const stage = folder + "/.folio-deleted", staged = stage + "/" + p.slice(p.lastIndexOf("/") + 1);
        dismiss();
        run(["sh", "-c", "mkdir -p -- \"$2\" && mv -f -- \"$1\" \"$2/\"", "sh", p, stage], ok => {
            if (!ok) { Toasts.show("Could not delete the screenshot", { "icon": "image" }); return; }
            // Commit: back to its place, then to the Trash, so the Trash
            // restores it where it was. Undo: back to its place.
            Toasts.undo("Screenshot deleted", () => {
                root.skip(p);
                const trash = fake ? ["rm", "-f", "--", staged] : ["sh", "-c", "mv -n -- \"$1\" \"$2\" && gio trash -- \"$2\"", "sh", staged, p];
                run(trash, done => {
                    run(["rmdir", "--", stage]);
                    if (!done) Toasts.show("Could not move the screenshot to the Trash", { "icon": "image" });
                });
            }, () => {
                root.skip(p);
                run(["mv", "-n", "--", staged, p], done => { run(["rmdir", "--", stage]); if (done) root.show(p, fake); });
            }, "image");
        });
    }

    // One-off commands with a callback on exit (true when they succeeded).
    Component {
        id: job
        Process {
            property var done: null
            onExited: code => { if (done) done(code === 0); destroy(); }
        }
    }
    function run(cmd, done) {
        const p = job.createObject(root, { "command": cmd, "done": done || null });
        p.running = true;
    }

    // Fixtures copy a plate into the runtime dir and show it; nothing real
    // opens or goes to the Trash.
    IpcHandler {
        target: "screenshot"
        function show(path: string): void { root.show(path, false); }
        function hide(): void { root.dismiss(); }
        // What the thumbnail's buttons do, for keybinds and tests.
        function open(): void { if (root.shown) root.open(); }
        function copy(): void { if (root.shown) root.copy(); }
        function remove(): void { if (root.shown) root.remove(); }
        function fixture(name: string): void {
            if (name !== "normal" && name !== "stress") { root.dismiss(); return; }
            const src = (name === "stress" ? Art.portrait(Art.current) : Art.mask(Art.current)).replace("file://", "");
            const dst = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/folio-screenshot-fixture/" + (name === "stress"
                ? "Screenshot from 2026-10-28 22-41-07 — Quarterly planning with product, design and the extended team.png"
                : "Screenshot from 2026-10-28 22-41-07.png");
            root.run(["sh", "-c", "mkdir -p -- \"$(dirname -- \"$2\")\" && cp -f -- \"$1\" \"$2\"", "sh", src, dst], ok => { if (ok) root.show(dst, true); });
        }
    }

    // New screenshots: inotifywait when installed, else the newest file every
    // 2 s. Either way only files that appear after the shell starts. Files
    // left aside by a Delete the shell never committed go to the Trash first.
    Process {
        running: true
        command: ["sh", "-c", `
            d=$1
            for f in "$d"/.folio-deleted/*; do
                [ -f "$f" ] || continue
                n=$d/\${f##*/}
                mv -n -- "$f" "$n" && gio trash -- "$n" 2>/dev/null
            done
            rmdir -- "$d/.folio-deleted" 2>/dev/null
            if command -v inotifywait >/dev/null 2>&1 && [ -d "$d" ]; then
                exec inotifywait -m -q -e close_write -e moved_to --format '%w%f' --exclude '/\\.' "$d"
            fi
            newest() { find "$d" -maxdepth 1 -type f -name '*.png' ! -name '.*' -printf '%T@ %p\\n' 2>/dev/null | sort -n | tail -n 1; }
            last=$(newest); last=\${last%% *}; last=\${last:-0}
            while sleep 2; do
                n=$(newest); [ -n "$n" ] || continue
                t=\${n%% *}
                if awk -v a="$t" -v b="$last" 'BEGIN { exit !(a > b) }'; then
                    last=$t; sleep 0.4; printf '%s\\n' "\${n#* }"
                fi
            done`, "sh", root.dir]
        stdout: SplitParser {
            onRead: line => {
                if (!/\.png$/i.test(line) || Date.now() - (root.restoring[line] || 0) < 5000) return;
                Sounds.play("screenshot");
                root.show(line, false);
            }
        }
    }

    PanelWindow {
        id: win
        screen: Shell.screenFor(Quickshell.screens)
        visible: root.shown || card.x < width
        color: "transparent"
        anchors { bottom: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: card.width + 16 + 48
        implicitHeight: card.height + 90 + 48
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "folio:screenshot"
        mask: Region { item: card }
        BackgroundEffect.blurRegion: Region { item: card; radius: Theme.rL + frost.extra }
        BlurNudge { id: frost; key: root.shown }

        // Holds while hovered, pressed or dragged.
        Timer {
            id: stay
            interval: 6000
            running: root.shown && !hover.hovered && !gesture.pressed && !proxy.Drag.active
            onTriggered: root.dismiss()
        }
        Connections {
            target: root
            // A new picture prints in once it has loaded.
            function onShownAgain() {
                stay.restart();
                shot.progress = 0;
                if (picture.status === Image.Ready) shot.printIn(700); else shot.waiting = true;
            }
        }

        Item {
            id: card
            width: 240
            height: 150
            y: win.height - 90 - height
            property real swipe: 0
            x: (root.shown ? win.width - 16 - width : win.width + 24) + swipe
            Behavior on x { enabled: gesture.mode !== "swipe"; SpringPanel {} }

            HoverHandler { id: hover }

            Sheet {
                anchors.fill: parent
                radius: Theme.rL
            }
            ClippingRectangle {
                id: frame
                anchors.fill: parent
                anchors.margins: 6
                radius: Theme.inner(Theme.rL, 6)
                color: Theme.well

                Develop {
                    id: shot
                    property bool waiting: false
                    anchors.fill: parent
                    grain: 1
                    Image {
                        id: picture
                        anchors.fill: parent
                        source: root.url
                        sourceSize: Qt.size(480, 300)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        smooth: true
                        mipmap: true
                        onStatusChanged: if (status !== Image.Loading && shot.waiting) { shot.waiting = false; shot.printIn(700); }
                    }
                }

                // Hover: what it is, and what it can do.
                Item {
                    anchors.fill: parent
                    opacity: hover.hovered && gesture.mode === "" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: Theme.tQuick; easing.type: Easing.OutCubic } }
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.45; color: "transparent" }
                            GradientStop { position: 1.0; color: Theme.rgba(Theme.shade, 0.32) }
                        }
                    }
                    Rectangle {
                        x: 6; y: 6
                        width: Math.min(parent.width - 44, caption.implicitWidth + 14)
                        height: 22
                        radius: Theme.inner(frame.radius, 6)
                        color: Theme.sheetStrong
                        Cap { id: caption; anchors.centerIn: parent; width: parent.width - 14; text: root.title || "Screenshot" }
                    }
                    Row {
                        x: 6
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        spacing: 6
                        ThumbButton { text: copied.running ? "Copied" : "Copy"; onClicked: { root.copy(); copied.restart(); } }
                        ThumbButton { text: "Delete"; danger: true; onClicked: root.remove() }
                    }
                    ThumbButton {
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        y: 6
                        glyph: "close"
                        onClicked: root.dismiss()
                    }
                    Timer { id: copied; interval: 1400 }
                }
            }

            // Click opens; a drag right dismisses; any other drag carries the
            // file out (text/uri-list) to wherever it is dropped.
            MouseArea {
                id: gesture
                anchors.fill: parent
                z: -1
                cursorShape: mode === "drag" ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                property string mode: ""
                property point start
                property real lastX: 0
                property real lastT: 0
                property real speed: 0
                onPressed: m => {
                    const p = mapToItem(null, m.x, m.y);
                    start = p; lastX = p.x; lastT = Date.now(); speed = 0; mode = "";
                }
                onPositionChanged: m => {
                    const p = mapToItem(null, m.x, m.y);
                    const dx = p.x - start.x, dy = p.y - start.y;
                    if (mode === "" && Math.hypot(dx, dy) > 10) {
                        mode = dx > 0 && Math.abs(dx) > Math.abs(dy) ? "swipe" : "drag";
                        if (mode === "drag") proxy.Drag.active = true;
                    }
                    if (mode === "swipe") {
                        const now = Date.now();
                        speed = (p.x - lastX) / Math.max(1, now - lastT);
                        lastX = p.x; lastT = now;
                        card.swipe = dx > 0 ? dx : dx / 4;
                    }
                }
                onReleased: {
                    const was = mode;
                    mode = "";
                    if (was === "swipe") {
                        if (card.swipe > 70 || speed > 0.6) root.dismiss();
                        card.swipe = 0;
                    } else if (was === "") {
                        root.open();
                    }
                }
                onCanceled: { mode = ""; card.swipe = 0; }
            }
            Item {
                id: proxy
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction
                Drag.mimeData: ({ "text/uri-list": root.url + "\r\n" })
                Drag.imageSource: root.url
                Drag.imageSourceSize: Qt.size(160, 100)
                Drag.onDragFinished: action => {
                    gesture.mode = "";
                    if (action !== Qt.IgnoreAction) root.dismiss();
                }
            }
        }
    }
}
