import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets
import "DisplayArrange.js" as Arrange

// The desk seen from above: each display that is on, to scale, showing the
// plate. Drag one to move it; it lands touching a neighbour and the rest
// re-centre on springs. Displays that are off wait in a row underneath.
Item {
    id: canvas
    property var outputs: []
    property string selected
    signal select(string key)
    signal moved(var positions)

    readonly property var on: outputs.filter(o => o.on)
    readonly property var off: outputs.filter(o => !o.on)
    function output(key) { return outputs.find(o => o.key === key) || null; }

    // Where a dropped display was put, until niri reports it there.
    property var pending: ({})
    Timer { id: forget; interval: 2500; onTriggered: canvas.pending = {} }
    onOutputsChanged: {
        const p = {};
        for (const k in pending) { const o = output(k); if (o && (o.x !== pending[k].x || o.y !== pending[k].y)) p[k] = pending[k]; }
        pending = p;
        sync();
    }
    function rectOf(o) { const p = pending[o.key]; return { "x": p ? p.x : o.x, "y": p ? p.y : o.y, "w": o.w, "h": o.h }; }
    readonly property var rects: { const r = {}; for (const o of on) r[o.key] = rectOf(o); return r; }
    readonly property var bounds: {
        const ks = Object.keys(rects);
        if (!ks.length) return { "x": 0, "y": 0, "w": 1920, "h": 1080 };
        const x0 = Math.min.apply(null, ks.map(k => rects[k].x)), y0 = Math.min.apply(null, ks.map(k => rects[k].y));
        const x1 = Math.max.apply(null, ks.map(k => rects[k].x + rects[k].w)), y1 = Math.max.apply(null, ks.map(k => rects[k].y + rects[k].h));
        return { "x": x0, "y": y0, "w": Math.max(1, x1 - x0), "h": Math.max(1, y1 - y0) };
    }
    readonly property real band: off.length ? 54 : 0
    readonly property real s: Math.min((width - 40) / bounds.w, (height - band - 40) / bounds.h)
    readonly property real ox: (width - bounds.w * s) / 2
    readonly property real oy: (height - band - bounds.h * s) / 2

    function drop(key, dx, dy) {
        const r = Object.assign({}, rects);
        const m = r[key];
        const at = Arrange.snap(r, key, m.x + dx / s, m.y + dy / s, 14 / s);
        r[key] = Object.assign({}, m, at);
        const pos = Arrange.normalize(r);
        pending = pos;
        forget.restart();
        moved(pos);
    }

    // One tile per display, kept by key so moves glide instead of re-creating.
    ListModel { id: tiles }
    function sync() {
        const keys = on.map(o => o.key);
        for (let i = tiles.count - 1; i >= 0; i--) if (keys.indexOf(tiles.get(i).key) < 0) tiles.remove(i);
        for (const k of keys) { let found = false; for (let i = 0; i < tiles.count; i++) if (tiles.get(i).key === k) found = true; if (!found) tiles.append({ "key": k }); }
    }
    Component.onCompleted: sync()

    Repeater {
        model: tiles
        Item {
            id: tile
            required property string key
            readonly property var o: canvas.output(key)
            readonly property var r: o ? canvas.rectOf(o) : { "x": 0, "y": 0, "w": 0, "h": 0 }
            readonly property bool chosen: canvas.selected === key
            property real dx: 0
            property real dy: 0
            visible: !!o
            x: canvas.ox + (r.x - canvas.bounds.x) * canvas.s + dx
            y: canvas.oy + (r.y - canvas.bounds.y) * canvas.s + dy
            width: r.w * canvas.s
            height: r.h * canvas.s
            z: area.pressed ? 2 : chosen ? 1 : 0
            Behavior on x { enabled: !area.pressed; SpringPanel {} }
            Behavior on y { enabled: !area.pressed; SpringPanel {} }
            Behavior on width { SpringPanel {} }
            Behavior on height { SpringPanel {} }
            scale: area.pressed ? 1.02 : 1
            Behavior on scale { SpringPress {} }

            Rectangle {
                anchors.fill: parent
                radius: Theme.rXs
                color: Theme.paper
                clip: true
                Plate {
                    anchors.fill: parent; anchors.margins: 1
                    textureWidth: 640; developOnLoad: false; breathe: 0
                    opacity: tile.chosen ? 1 : 0.75
                }
                // The bar, so the displays read as screens.
                Rectangle { width: parent.width; height: Math.max(3, 34 * canvas.s); color: Theme.rgba(Theme.sheetBase, 0.85) }
            }
            Rectangle {
                anchors.fill: parent
                radius: Theme.rXs
                color: "transparent"
                border.width: tile.chosen ? 2 : 1
                border.color: tile.chosen ? Theme.ink : Theme.ruleStrong
            }
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - 10, tag.implicitWidth + 18)
                height: tag.implicitHeight + 10
                radius: Theme.rS
                color: Theme.sheetStrong
                visible: parent.width > 54 && parent.height > 30
                Column {
                    id: tag
                    anchors.centerIn: parent
                    Label { anchors.horizontalCenter: parent.horizontalCenter; width: Math.min(implicitWidth, tile.width - 28); text: tile.o ? tile.o.label : ""; font.weight: Font.DemiBold; font.pixelSize: Theme.fsS }
                    Cap { anchors.horizontalCenter: parent.horizontalCenter; width: Math.min(implicitWidth, tile.width - 28); visible: tile.height > 64; text: tile.o ? tile.o.mode.replace(/@.*/, "").replace("x", " × ") + " · " + Math.round(tile.o.scale * 100) + "%" : "" }
                }
            }
            MouseArea {
                id: area
                anchors.fill: parent
                preventStealing: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property point start
                onPressed: mouse => { start = mapToItem(canvas, mouse.x, mouse.y); canvas.select(tile.key); }
                onPositionChanged: mouse => {
                    const p = mapToItem(canvas, mouse.x, mouse.y);
                    tile.dx = p.x - start.x; tile.dy = p.y - start.y;
                }
                onReleased: {
                    const dx = tile.dx, dy = tile.dy;
                    if (Math.abs(dx) + Math.abs(dy) > 3 && canvas.on.length > 1) canvas.drop(tile.key, dx, dy);
                    tile.dx = 0; tile.dy = 0;
                }
            }
        }
    }

    // Displays that are off.
    Row {
        visible: canvas.off.length > 0
        anchors { left: parent.left; bottom: parent.bottom; leftMargin: 4 }
        spacing: 8
        Cap { text: "Off"; anchors.verticalCenter: parent.verticalCenter; width: 30 }
        Repeater {
            model: canvas.off
            Rectangle {
                required property var modelData
                width: offLabel.implicitWidth + 24; height: 34
                radius: Theme.rS
                color: canvas.selected === modelData.key ? Theme.well : "transparent"
                border.width: canvas.selected === modelData.key ? 2 : 1
                border.color: canvas.selected === modelData.key ? Theme.ink : Theme.ruleStrong
                Label { id: offLabel; anchors.centerIn: parent; width: Math.min(implicitWidth, 200); text: modelData.label; color: Theme.text2; font.pixelSize: Theme.fsS }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: canvas.select(modelData.key) }
            }
        }
    }
}
