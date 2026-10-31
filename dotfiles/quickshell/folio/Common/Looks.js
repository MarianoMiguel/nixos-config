.pragma library

// Interstellar's looks, as tools/azure-folio/looks.py has them: each theme's
// named colors and derive(), which keeps a pick's hue and moves its lightness
// until it reads. test_looks.py runs this file against the Python and fails
// if they ever disagree, so the shell shows a pick exactly as apps get it.

var THEMES = ["folio", "lumen"];
var INKS = { "azure": ["#214c94", "#adc7ed"], "cobalt": ["#244fb8", "#9dbbfa"], "slate": ["#35556e", "#adc3d2"] };
var ACCENTS = { "blue": "#0a7aff", "purple": "#a050e8", "pink": "#ef4f97", "red": "#f2453a", "orange": "#ff8a00",
                "yellow": "#ffc800", "green": "#30c35a", "teal": "#2bb3c8", "graphite": "#8a8a90" };
var NAMED = { "folio": INKS, "lumen": ACCENTS };
var DEFAULT = { "folio": "azure", "lumen": "blue" };
var BACKGROUND = { "folio": { "light": "#f7f4e9", "dark": "#101d33" }, "lumen": { "light": "#ffffff", "dark": "#1e1e20" } };
var INK_ON_LIGHT = "#1d1d1f";
var HEX = /^#[0-9a-fA-F]{6}$/;

function validPick(theme, pick) {
    return THEMES.indexOf(theme) >= 0 && typeof pick === "string" && (pick in NAMED[theme] || HEX.test(pick));
}

// The swatch a named pick shows before derive(): Folio's light ink, Lumen's color.
function named(theme, name) { return theme === "folio" ? INKS[name][0] : ACCENTS[name]; }

function lin(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
function gam(c) { return c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055; }
function rgb(h) { return [1, 3, 5].map(function (i) { return parseInt(h.slice(i, i + 2), 16) / 255; }); }
// Python's round(): halves go to the even neighbour.
function roundEven(x) { var f = Math.floor(x), d = x - f; return d > 0.5 ? f + 1 : d < 0.5 ? f : (f % 2 === 0 ? f : f + 1); }
function toHex(v) {
    return "#" + v.map(function (x) { var n = roundEven(Math.min(1, Math.max(0, x)) * 255); return (n < 16 ? "0" : "") + n.toString(16); }).join("");
}

function oklch(h) {
    var c = rgb(h).map(lin), r = c[0], g = c[1], b = c[2];
    var l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    var m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    var s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    var L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
    var A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
    var B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
    return [L, Math.hypot(A, B), ((Math.atan2(B, A) * 180 / Math.PI) + 360) % 360];
}

function linear(L, C, h) {
    var A = C * Math.cos(h * Math.PI / 180), B = C * Math.sin(h * Math.PI / 180);
    var l = Math.pow(L + 0.3963377774 * A + 0.2158037573 * B, 3);
    var m = Math.pow(L - 0.1055613458 * A - 0.0638541728 * B, 3);
    var s = Math.pow(L - 0.0894841775 * A - 1.291485548 * B, 3);
    return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s];
}

function outside(v) { return v.some(function (x) { return x < -1e-4 || x > 1 + 1e-4; }); }

// OKLCH to sRGB hex, giving up chroma (never hue or lightness) to stay in gamut.
function lch(L, C, h) {
    var c = C, v = linear(L, C, h);
    while (c > 0 && outside(v)) { c -= 0.004; v = linear(L, Math.max(0, c), h); }
    return toHex(v.map(function (x) { return gam(Math.min(1, Math.max(0, x))); }));
}

function luminance(h) { var c = rgb(h).map(lin); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; }
function contrast(a, b) { var x = luminance(a), y = luminance(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); }

// [color, text on it] for a pick in a theme and mode.
function derive(theme, mode, pick) {
    if (!validPick(theme, pick)) { theme = theme === "lumen" ? "lumen" : "folio"; pick = DEFAULT[theme]; }
    var bg = BACKGROUND[theme][mode];
    if (theme === "folio" && pick in INKS) return [INKS[pick][mode === "light" ? 0 : 1], bg];
    pick = (theme === "lumen" && pick in ACCENTS ? ACCENTS[pick] : pick).toLowerCase();
    var o = oklch(pick), L0 = o[0], C0 = o[1], h = o[2];
    var C = theme === "folio" ? (mode === "light" ? Math.min(C0, 0.16) : Math.min(C0 * 0.55, 0.08)) : C0;
    var best = null;
    for (var i = 0; i < 155; i++) {
        var L = 0.2 + i * 0.005;
        var c = lch(L, C, h);
        var cost = Math.abs(L - L0), on;
        if (theme === "folio") {
            if (contrast(c, bg) < (mode === "light" ? 7 : 9)) continue;
            on = bg;
        } else {
            if (contrast(c, bg) < 3) continue;
            if (contrast("#ffffff", c) >= 4.5) on = "#ffffff";
            else if (contrast(INK_ON_LIGHT, c) >= 4.5) { on = INK_ON_LIGHT; cost += 0.1; }
            else continue;
        }
        if (best === null || cost < best[0]) best = [cost, c, on];
    }
    return best ? [best[1], best[2]] : [pick, theme === "folio" ? bg : "#ffffff"];
}
