import QtQuick
import qs.Common

// A day at a glance: a pill of halftone dots, dense from dusk to dawn and
// gone at noon, with the sun (an ink dot in a paper halo) at the hour.
Canvas {
    id: root
    property real hour: 12              // 0..24, local to the city
    readonly property real night: Math.max(0, Math.min(1, Math.abs(hour - 13) / 7 - 0.35))
    readonly property color ink: Theme.ink
    readonly property color well: Theme.well
    readonly property color halo: Theme.rgba(Theme.paper, 0.8)

    function css(c) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + c.a + ")"; }
    onNightChanged: requestPaint()
    onHourChanged: requestPaint()
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        const w = width, h = height, r = h / 2;
        ctx.reset();
        ctx.beginPath();
        ctx.moveTo(r, 0); ctx.lineTo(w - r, 0); ctx.arc(w - r, r, r, -Math.PI / 2, Math.PI / 2); ctx.lineTo(r, h); ctx.arc(r, r, r, Math.PI / 2, Math.PI * 1.5);
        ctx.closePath();
        ctx.clip();
        ctx.fillStyle = css(root.well);
        ctx.fillRect(0, 0, w, h);
        // Night: 0.9 px dots on a 3 px grid.
        if (root.night > 0.01) {
            ctx.globalAlpha = root.night;
            ctx.fillStyle = css(root.ink);
            ctx.beginPath();
            for (let y = 1.5; y < h; y += 3)
                for (let x = 1.5; x < w; x += 3) { ctx.moveTo(x + 0.9, y); ctx.arc(x, y, 0.9, 0, Math.PI * 2); }
            ctx.fill();
            ctx.globalAlpha = 1;
        }
        const sx = root.hour / 24 * w;
        ctx.beginPath(); ctx.arc(sx, r, 7, 0, Math.PI * 2); ctx.fillStyle = css(root.halo); ctx.fill();
        ctx.beginPath(); ctx.arc(sx, r, 4, 0, Math.PI * 2); ctx.fillStyle = css(root.ink); ctx.fill();
    }
}
