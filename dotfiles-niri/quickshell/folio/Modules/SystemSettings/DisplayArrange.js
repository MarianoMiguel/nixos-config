// Arranging displays: where a dragged display lands. Rects are in niri's
// logical pixels, {key: {x, y, w, h}}.
.pragma library

// The spot nearest (px, py) where `key` touches another display edge to edge
// (sharing at least a little of that edge, so the pointer can cross) without
// overlapping any; along the edge it aligns to the other's start, end or
// centre when within `threshold`. Returns {x, y}, or the old place if nothing fits.
function snap(rects, key, px, py, threshold) {
    const m = rects[key];
    const others = Object.keys(rects).filter(k => k !== key).map(k => rects[k]);
    if (others.length === 0) return { "x": 0, "y": 0 };
    const overlaps = (x, y) => others.some(o => x < o.x + o.w - 0.5 && x + m.w > o.x + 0.5 && y < o.y + o.h - 0.5 && y + m.h > o.y + 0.5);
    const align = (v, targets) => {
        let best = v, d = threshold;
        for (const t of targets) if (Math.abs(v - t) < d) { d = Math.abs(v - t); best = t; }
        return best;
    };
    const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
    let best = null, bestD = Infinity;
    const consider = (x, y) => {
        if (overlaps(x, y)) return;
        const d = Math.hypot(x - px, y - py);
        if (d < bestD) { bestD = d; best = { "x": Math.round(x), "y": Math.round(y) }; }
    };
    for (const o of others) {
        const shareY = Math.min(80, m.h / 4, o.h / 4), shareX = Math.min(80, m.w / 4, o.w / 4);
        for (const x of [o.x + o.w, o.x - m.w]) {
            const y = align(clamp(py, o.y - m.h + shareY, o.y + o.h - shareY), [o.y, o.y + o.h - m.h, o.y + (o.h - m.h) / 2]);
            consider(x, y);
        }
        for (const y of [o.y + o.h, o.y - m.h]) {
            const x = align(clamp(px, o.x - m.w + shareX, o.x + o.w - shareX), [o.x, o.x + o.w - m.w, o.x + (o.w - m.w) / 2]);
            consider(x, y);
        }
    }
    return best || { "x": m.x, "y": m.y };
}

// The arrangement moved so its top-left corner is 0,0.
function normalize(rects) {
    const keys = Object.keys(rects);
    const minX = Math.min.apply(null, keys.map(k => rects[k].x));
    const minY = Math.min.apply(null, keys.map(k => rects[k].y));
    const out = {};
    for (const k of keys) out[k] = { "x": Math.round(rects[k].x - minX), "y": Math.round(rects[k].y - minY) };
    return out;
}
