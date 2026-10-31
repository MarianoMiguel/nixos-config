import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// The battery's last day (Power & battery): one ink line over a faint wash,
// hairlines at 0, 50 and 100 %, the hours along the bottom, and under the
// plot a strip where the charger was in. The level now sits at the line's
// end. Hovering shows the time and level under the pointer.
Item {
    id: root
    property var points: []                 // [{t: seconds, v: percent, s: UPower state}], oldest first
    property real level: -1                 // the level now, drawn at the end
    property bool plugged: false            // plugged in now (continues the strip)
    property real span: 86400
    property real now: Date.now() / 1000
    Timer { interval: 60000; repeat: true; running: true; onTriggered: root.now = Date.now() / 1000 }
    implicitHeight: 176
    Layout.fillWidth: true

    // UPower states that mean the charger was in: charging, full, pending.
    function pluggedState(s) { return s === 1 || s === 4 || s === 5; }

    readonly property real padL: 40
    readonly property real padR: 14
    property string title: "Last 24 hours"
    readonly property real plotTop: 32
    readonly property real plotH: height - plotTop - 44
    readonly property real plotW: width - padL - padR
    function xOf(t) { return padL + (t - (now - span)) / span * plotW; }
    function yOf(v) { return plotTop + (1 - v / 100) * plotH; }

    // The points in the window, the one before it (so the line starts at the
    // left edge) and the level now at the end.
    readonly property var series: {
        const from = now - span, p = points || [], out = [];
        let before = null;
        for (const q of p) {
            if (q.t < from) { before = q; continue; }
            if (q.t <= now) out.push(q);
        }
        if (before && out.length) out.unshift({ "t": from, "v": before.v + (out[0].v - before.v) * (from - before.t) / Math.max(1, out[0].t - before.t), "s": before.s });
        if (level >= 0 && out.length) out.push({ "t": now, "v": level, "s": plugged ? 1 : 2 });
        return out;
    }
    readonly property bool empty: series.length < 2

    onSeriesChanged: plot.requestPaint()
    onWidthChanged: plot.requestPaint()
    onHeightChanged: plot.requestPaint()
    Connections {
        target: Theme
        function onInkChanged() { plot.requestPaint(); }
        function onPaperChanged() { plot.requestPaint(); }
    }

    // Hairlines and their labels.
    Repeater {
        model: [100, 50, 0]
        Item {
            required property int modelData
            Rectangle { x: root.padL; width: root.plotW; height: 1; y: Math.round(root.yOf(modelData)); color: Theme.rule }
            Cap { text: modelData + "%"; width: root.padL - 8; horizontalAlignment: Text.AlignRight; y: root.yOf(modelData) - height / 2 }
        }
    }

    Canvas {
        id: plot
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const s = root.series;
            if (s.length < 2) return;
            const ink = Theme.ink;
            const css = a => "rgba(" + Math.round(ink.r * 255) + "," + Math.round(ink.g * 255) + "," + Math.round(ink.b * 255) + "," + a + ")";
            // The wash under the line.
            ctx.beginPath();
            ctx.moveTo(root.xOf(s[0].t), root.yOf(0));
            for (const q of s) ctx.lineTo(root.xOf(q.t), root.yOf(q.v));
            ctx.lineTo(root.xOf(s[s.length - 1].t), root.yOf(0));
            ctx.closePath();
            ctx.fillStyle = css(0.10);
            ctx.fill();
            // The line.
            ctx.beginPath();
            s.forEach((q, i) => { if (i) ctx.lineTo(root.xOf(q.t), root.yOf(q.v)); else ctx.moveTo(root.xOf(q.t), root.yOf(q.v)); });
            ctx.strokeStyle = css(1);
            ctx.lineWidth = 2;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";
            ctx.stroke();
            // Where the charger was in: a strip under the plot.
            const y = root.plotTop + root.plotH + 8;
            ctx.fillStyle = css(0.55);
            for (let i = 0; i < s.length - 1; i++) {
                if (!root.pluggedState(s[i].s)) continue;
                const x0 = root.xOf(s[i].t), x1 = root.xOf(s[i + 1].t);
                if (x1 - x0 >= 1) ctx.fillRect(x0, y, x1 - x0, 4);
            }
        }
    }
    // The track the strip sits on.
    Rectangle { x: root.padL; y: root.plotTop + root.plotH + 8; width: root.plotW; height: 4; radius: 2; color: Theme.well; z: -1 }

    // The level now, at the line's end.
    Rectangle {
        visible: !root.empty
        width: 12; height: 12; radius: 6
        x: root.xOf(root.now) - 6; y: root.yOf(root.series.length ? root.series[root.series.length - 1].v : 0) - 6
        color: Theme.ink
        border.width: 2; border.color: Theme.mix(Theme.paper, Theme.tint, 0.09)
    }

    // Hours along the bottom: every six on the clock.
    Repeater {
        model: {
            const out = [], first = Math.ceil((root.now - root.span) / 21600) * 21600;
            for (let t = first; t <= root.now; t += 21600) out.push(t);
            return out;
        }
        Cap {
            required property real modelData
            text: Qt.formatTime(new Date(modelData * 1000), "HH:mm")
            x: Math.max(root.padL, Math.min(root.width - root.padR - implicitWidth, root.xOf(modelData) - implicitWidth / 2))
            y: root.plotTop + root.plotH + 20
        }
    }
    Cap { text: root.title; y: 0 }
    // The strip's key, so the strip is never colour alone.
    Row {
        visible: !root.empty
        anchors.right: parent.right; anchors.rightMargin: root.padR
        y: 0
        spacing: 6
        Rectangle { width: 14; height: 4; radius: 2; color: Theme.rgba(Theme.ink, 0.55); anchors.verticalCenter: parent.verticalCenter }
        Cap { text: "Plugged in" }
    }

    Label {
        visible: root.empty
        anchors.centerIn: parent
        text: "No history yet. UPower records it as the battery charges and drains."
        color: Theme.text3; font.pixelSize: Theme.fsS
        width: Math.min(implicitWidth, parent.width - 32)
    }

    // Hover: a hairline and the reading under the pointer.
    HoverHandler { id: hover; enabled: !root.empty }
    readonly property var hovered: {
        if (!hover.hovered || root.empty) return null;
        const t = root.now - root.span + (hover.point.position.x - root.padL) / root.plotW * root.span;
        let best = null;
        for (const q of root.series) if (!best || Math.abs(q.t - t) < Math.abs(best.t - t)) best = q;
        return best;
    }
    Rectangle {
        visible: !!root.hovered
        x: root.hovered ? Math.round(root.xOf(root.hovered.t)) : 0
        y: root.plotTop; width: 1; height: root.plotH
        color: Theme.ruleStrong
    }
    Rectangle {
        id: tip
        visible: !!root.hovered
        readonly property real cx: root.hovered ? root.xOf(root.hovered.t) : 0
        x: Math.max(root.padL, Math.min(root.width - width, cx - width / 2))
        y: root.hovered ? Math.max(0, root.yOf(root.hovered.v) - height - 10) : 0
        width: tipText.implicitWidth + 16; height: 24; radius: 8
        color: Theme.sheetStrong; border.color: Theme.rule
        Label {
            id: tipText
            anchors.centerIn: parent
            font.pixelSize: Theme.fsS; font.features: { "tnum": 1 }
            text: root.hovered ? Qt.formatTime(new Date(root.hovered.t * 1000), "HH:mm") + " · " + Math.round(root.hovered.v) + "%" + (root.pluggedState(root.hovered.s) ? " · plugged in" : "") : ""
        }
    }
}
