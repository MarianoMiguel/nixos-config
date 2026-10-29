.pragma library

// The launcher's pure helpers: a safe arithmetic parser (never eval), unit
// conversions, match scores for actions, emoji and files, and short human
// times and sizes.

// Arithmetic: + − × ÷ ^ %, parentheses, decimals. "50%" is a percent, "7 % 3"
// a remainder; unclosed parentheses close at the end. Returns null unless the
// whole text is an expression with at least one operator.
function calc(input) {
    let s = String(input || "").trim();
    if (s.startsWith("=")) s = s.slice(1);
    if (!s || s.length > 160 || !/[0-9]/.test(s)) return null;
    const toks = [];
    let i = 0, ops = 0;
    while (i < s.length) {
        const c = s[i];
        if (c === " ") { i++; continue; }
        if (/[0-9.,]/.test(c)) {
            let j = i;
            while (j < s.length && /[0-9.,]/.test(s[j])) j++;
            const raw = s.slice(i, j).replace(",", ".");
            if (!/^(\d+\.?\d*|\.\d+)$/.test(raw)) return null;
            toks.push({ "t": "n", "v": parseFloat(raw) });
            i = j;
            continue;
        }
        const op = { "+": "+", "-": "-", "−": "-", "*": "*", "×": "*", "x": "*", "/": "/", "÷": "/", "^": "^", "%": "%", "(": "(", ")": ")" }[c];
        if (!op) return null;
        if (op !== ")") ops++;
        toks.push({ "t": op });
        i++;
    }
    if (ops === 0) return null;
    let p = 0;
    const peek = () => toks[p] ? toks[p].t : "";
    // After a number, % is a remainder only when another number follows.
    const startsOperand = t => t === "n" || t === "(";
    function expr() {
        let v = term();
        while (peek() === "+" || peek() === "-") { const o = toks[p++].t; const r = term(); v = o === "+" ? v + r : v - r; }
        return v;
    }
    function term() {
        let v = unary();
        while (peek() === "*" || peek() === "/" || (peek() === "%" && startsOperand(toks[p + 1] ? toks[p + 1].t : ""))) {
            const o = toks[p++].t; const r = unary();
            v = o === "*" ? v * r : o === "/" ? v / r : v % r;
        }
        return v;
    }
    function unary() {
        if (peek() === "-") { p++; return -unary(); }
        if (peek() === "+") { p++; return unary(); }
        return power();
    }
    function power() {
        const b = postfix();
        if (peek() === "^") { p++; return Math.pow(b, unary()); }
        return b;
    }
    function postfix() {
        let v = primary();
        while (peek() === "%" && !startsOperand(toks[p + 1] ? toks[p + 1].t : "")) { p++; v = v / 100; }
        return v;
    }
    function primary() {
        const t = toks[p];
        if (!t) throw "end";
        if (t.t === "n") { p++; return t.v; }
        if (t.t === "(") {
            p++;
            const v = expr();
            if (peek() === ")") p++;
            else if (p < toks.length) throw "paren";
            return v;
        }
        throw "token";
    }
    try {
        const v = expr();
        if (p !== toks.length || !isFinite(v)) return null;
        return { "expression": s.trim(), "value": v, "text": format(v) };
    } catch (e) {
        return null;
    }
}

// Twelve significant digits hide float noise (0.1 + 0.2 = 0.3).
function format(v) {
    if (v === 0) return "0";
    const a = Math.abs(v);
    if (a >= 1e15 || a < 1e-9) return v.toExponential(6).replace(/\.?0+e/, "e");
    return String(Number(v.toPrecision(12)));
}

// Match quality of a query against a name and extra words (0 = no match),
// on the same scale as Apps.score. One letter matches word starts only.
function score(name, words, q) {
    name = String(name || "").toLowerCase();
    if (!q) return 0;
    if (name === q) return 100;
    if (name.startsWith(q)) return 80;
    if (name.split(/[\s-]/).some(w => w.startsWith(q))) return 60;
    if (q.length > 1 && name.indexOf(q) >= 0) return 40;
    const extra = String(words || "").toLowerCase();
    if (extra.split(/\s+/).some(w => w.startsWith(q))) return 30;
    if (q.length > 1 && extra.indexOf(q) >= 0) return 20;
    return 0;
}

function ago(time, now) {
    const s = Math.max(0, Math.round((now - time) / 1000));
    if (s < 45) return "just now";
    if (s < 3600) return Math.round(s / 60) + " min ago";
    if (s < 86400) return Math.round(s / 3600) + " h ago";
    return Math.round(s / 86400) + " d ago";
}

// One line for a list row: whitespace collapsed.
function oneLine(text) { return String(text || "").replace(/\s+/g, " ").trim(); }

// ---- Units: "5 km in mi", "70 f to c", "3 cups in ml", "1.5 GiB in MB",
// "2h30 in minutes", "5'10\" in cm", "1m80 in ft", "1/2 cup in tbsp". A
// quantity alone ("5 km", "70°F") converts to its usual counterpart. Returns
// null unless the text is a conversion between units of one kind.

const UNITS = {};           // every name, lowercase -> unit
const SYMBOL = {};          // symbol -> unit
function unit(kind, symbol, factor, names, offset) {
    const u = { "kind": kind, "symbol": symbol, "factor": factor, "offset": offset || 0 };
    SYMBOL[symbol] = u;
    for (const n of [symbol.toLowerCase()].concat(names || []))
        if (!UNITS[n]) UNITS[n] = u;
    return u;
}
// Length (m)
unit("Length", "mm", 0.001, ["millimeter", "millimetre"]);
unit("Length", "cm", 0.01, ["centimeter", "centimetre"]);
unit("Length", "m", 1, ["meter", "metre", "mt", "mts"]);
unit("Length", "km", 1000, ["kilometer", "kilometre", "kms"]);
unit("Length", "µm", 1e-6, ["um", "micron", "micrometer", "micrometre"]);
unit("Length", "nm", 1e-9, ["nanometer", "nanometre"]);
unit("Length", "in", 0.0254, ["inch", "inches", "\"", "″", "''"]);
unit("Length", "ft", 0.3048, ["foot", "feet", "'", "′"]);
unit("Length", "yd", 0.9144, ["yard"]);
unit("Length", "mi", 1609.344, ["mile"]);
unit("Length", "nmi", 1852, ["nautical mile"]);
unit("Length", "ly", 9460730472580800, ["light year", "light-year", "lightyear"]);
// Mass (kg)
unit("Mass", "mg", 1e-6, ["milligram"]);
unit("Mass", "g", 0.001, ["gram", "gr", "grs"]);
unit("Mass", "kg", 1, ["kilogram", "kilo", "kgs"]);
unit("Mass", "t", 1000, ["tonne", "metric ton"]);
unit("Mass", "ton", 907.18474, ["short ton", "us ton"]);
unit("Mass", "oz", 0.028349523125, ["ounce"]);
unit("Mass", "lb", 0.45359237, ["pound", "lbs"]);
unit("Mass", "st", 6.35029318, ["stone"]);
// Volume (l)
unit("Volume", "ml", 0.001, ["milliliter", "millilitre", "cc", "cm3", "cm³"]);
unit("Volume", "cl", 0.01, ["centiliter", "centilitre"]);
unit("Volume", "dl", 0.1, ["deciliter", "decilitre"]);
unit("Volume", "l", 1, ["liter", "litre", "lt", "ltr", "lts"]);
unit("Volume", "m³", 1000, ["m3", "cubic meter", "cubic metre"]);
unit("Volume", "tsp", 0.00492892159375, ["teaspoon"]);
unit("Volume", "tbsp", 0.01478676478125, ["tablespoon", "tbs"]);
unit("Volume", "fl oz", 0.0295735295625, ["floz", "fl. oz", "fluid ounce"]);
unit("Volume", "cup", 0.2365882365, []);
unit("Volume", "pt", 0.473176473, ["pint"]);
unit("Volume", "qt", 0.946352946, ["quart"]);
unit("Volume", "gal", 3.785411784, ["gallon"]);
unit("Volume", "ft³", 28.316846592, ["ft3", "cubic foot", "cubic feet"]);
// Temperature (K, with an offset)
unit("Temperature", "°C", 1, ["c", "ºc", "celsius", "centigrade", "degc"], 273.15);
unit("Temperature", "°F", 5 / 9, ["f", "ºf", "fahrenheit", "degf"], 273.15 - 32 * 5 / 9);
unit("Temperature", "K", 1, ["kelvin"]);
// Data (bytes): kB, MB… are powers of 1000, KiB, MiB… of 1024.
unit("Data", "B", 1, ["byte"]);
unit("Data", "kB", 1e3, ["kilobyte"]);
unit("Data", "MB", 1e6, ["megabyte"]);
unit("Data", "GB", 1e9, ["gigabyte"]);
unit("Data", "TB", 1e12, ["terabyte"]);
unit("Data", "PB", 1e15, ["petabyte"]);
unit("Data", "KiB", 1024, ["kibibyte"]);
unit("Data", "MiB", Math.pow(1024, 2), ["mebibyte"]);
unit("Data", "GiB", Math.pow(1024, 3), ["gibibyte"]);
unit("Data", "TiB", Math.pow(1024, 4), ["tebibyte"]);
unit("Data", "PiB", Math.pow(1024, 5), ["pebibyte"]);
unit("Data", "bit", 0.125, []);
unit("Data", "kbit", 125, ["kilobit", "kb/bit"]);
unit("Data", "Mbit", 125e3, ["megabit"]);
unit("Data", "Gbit", 125e6, ["gigabit"]);
unit("Data", "Tbit", 125e9, ["terabit"]);
// Time (s)
unit("Time", "ns", 1e-9, ["nanosecond"]);
unit("Time", "µs", 1e-6, ["us", "microsecond"]);
unit("Time", "ms", 0.001, ["millisecond", "msec"]);
unit("Time", "s", 1, ["sec", "secs", "second", "seg"]);
unit("Time", "min", 60, ["minute", "mins", "mn"]);
unit("Time", "h", 3600, ["hr", "hrs", "hour", "hs"]);
unit("Time", "d", 86400, ["day", "dia"]);
unit("Time", "wk", 604800, ["week"]);
unit("Time", "mo", 2629746, ["month"]);
unit("Time", "yr", 31556952, ["year", "y", "yrs"]);
// Speed (m/s)
unit("Speed", "m/s", 1, ["mps", "meter per second", "meters per second", "metre per second", "metres per second"]);
unit("Speed", "km/h", 1 / 3.6, ["kmh", "kph", "kmph", "km/hr", "km per hour", "kilometer per hour", "kilometers per hour", "kilometre per hour", "kilometres per hour"]);
unit("Speed", "mph", 0.44704, ["mi/h", "mile per hour", "miles per hour"]);
unit("Speed", "kn", 1852 / 3600, ["knot", "kt", "kts"]);
unit("Speed", "ft/s", 0.3048, ["fps", "foot per second", "feet per second"]);
// Area (m²)
unit("Area", "cm²", 1e-4, ["cm2"]);
unit("Area", "m²", 1, ["m2", "sqm"]);
unit("Area", "km²", 1e6, ["km2"]);
unit("Area", "ha", 1e4, ["hectare"]);
unit("Area", "acre", 4046.8564224, ["ac"]);
unit("Area", "ft²", 0.09290304, ["ft2", "sqft"]);
unit("Area", "in²", 0.00064516, ["in2"]);
unit("Area", "yd²", 0.83612736, ["yd2"]);
unit("Area", "mi²", 2589988.110336, ["mi2"]);
// Energy (J)
unit("Energy", "J", 1, ["joule"]);
unit("Energy", "kJ", 1000, ["kilojoule"]);
unit("Energy", "MJ", 1e6, ["megajoule"]);
unit("Energy", "cal", 4.184, ["calorie"]);
unit("Energy", "kcal", 4184, ["kilocalorie"]);
unit("Energy", "Wh", 3600, ["watt hour", "watt-hour"]);
unit("Energy", "kWh", 3.6e6, ["kilowatt hour", "kilowatt-hour"]);
unit("Energy", "BTU", 1055.05585262, []);
// Power (W)
unit("Power", "W", 1, ["watt"]);
unit("Power", "kW", 1000, ["kilowatt"]);
unit("Power", "hp", 745.69987158227, ["horsepower"]);
// Pressure (Pa)
unit("Pressure", "Pa", 1, ["pascal"]);
unit("Pressure", "hPa", 100, ["mbar", "millibar"]);
unit("Pressure", "kPa", 1000, []);
unit("Pressure", "bar", 1e5, []);
unit("Pressure", "psi", 6894.757293168, []);
unit("Pressure", "atm", 101325, ["atmosphere"]);
unit("Pressure", "mmHg", 133.322387415, ["torr"]);
// Angle (degrees)
unit("Angle", "°", 1, ["deg", "degree", "º"]);
unit("Angle", "rad", 180 / Math.PI, ["radian"]);
unit("Angle", "turn", 360, ["rev", "revolution"]);

// "5 km" alone converts to the unit people usually want next to it.
const COUNTERPART = {
    "km": "mi", "mi": "km", "m": "ft", "ft": "m", "cm": "in", "in": "cm", "mm": "in", "yd": "m", "nmi": "km",
    "kg": "lb", "lb": "kg", "g": "oz", "oz": "g", "st": "kg",
    "l": "gal", "gal": "l", "ml": "fl oz", "fl oz": "ml", "cup": "ml", "tbsp": "ml", "tsp": "ml", "pt": "ml", "qt": "l",
    "°C": "°F", "°F": "°C",
    "km/h": "mph", "mph": "km/h", "kn": "km/h", "m/s": "km/h",
    "GB": "GiB", "GiB": "GB", "MB": "MiB", "MiB": "MB", "TB": "TiB", "TiB": "TB",
    "ha": "acre", "acre": "ha", "m²": "ft²", "ft²": "m²", "km²": "mi²", "mi²": "km²",
    "kcal": "kJ", "kJ": "kcal", "psi": "bar", "bar": "psi", "kW": "hp", "hp": "kW", "rad": "°"
};
// Others worth seeing beside the answer, in order of preference.
const ALSO = {
    "Length": ["m", "km", "cm", "ft", "in", "mi"], "Mass": ["kg", "g", "lb", "oz"],
    "Volume": ["l", "ml", "cup", "fl oz", "gal"], "Temperature": ["°C", "°F", "K"],
    "Data": ["B", "kB", "MB", "GB", "TB", "KiB", "MiB", "GiB", "TiB"], "Time": ["s", "min", "h", "d", "wk"],
    "Speed": ["km/h", "mph", "m/s", "kn"], "Area": ["m²", "ft²", "ha", "acre", "km²"],
    "Energy": ["kJ", "kcal", "kWh", "J"], "Power": ["W", "kW", "hp"],
    "Pressure": ["kPa", "bar", "psi", "atm"], "Angle": ["°", "rad", "turn"]
};
// "2h30": a bare number after a unit counts in the next smaller one.
const SMALLER = { "h": "min", "min": "s", "d": "h", "wk": "d", "ft": "in", "lb": "oz", "st": "lb", "m": "cm", "km": "m", "yr": "mo" };
const SQUARE = { "cm": "cm²", "m": "m²", "km": "km²", "ft": "ft²", "in": "in²", "yd": "yd²", "mi": "mi²" };
const CUBIC = { "cm": "ml", "m": "m³", "ft": "ft³" };

function findUnit(raw) {
    const exact = String(raw || "").trim();
    // A capital before a small b is bits ("100 Mb").
    if (/^[KMGT]b$/.test(exact)) return SYMBOL[(exact[0] === "K" ? "k" : exact[0]) + "bit"];
    let t = exact.toLowerCase().replace(/\s+/g, " ").replace(/\.$/, "");
    t = t.replace(/^(degrees?|deg|grados?) /, "");
    const pow = /^(sq|square|cu|cubic) (.+)$/.exec(t);
    if (pow) {
        const base = findUnit(pow[2]);
        const to = base && (pow[1].startsWith("s") ? SQUARE : CUBIC)[base.symbol];
        return to ? SYMBOL[to] : null;
    }
    const n = t.replace(/ /g, "");
    for (const c of [t, t.endsWith("es") ? t.slice(0, -2) : "", t.endsWith("s") ? t.slice(0, -1) : "", n])
        if (c && UNITS[c]) return UNITS[c];
    return null;
}

function number(text) {
    const t = String(text).trim().replace("−", "-");
    if (/^[+-]?(\d+([.,]\d+)?|[.,]\d+)$/.test(t)) return parseFloat(t.replace(",", "."));
    const c = calc(t);
    return c ? c.value : null;
}

// A quantity: one number (or sum) and a unit, or several of one kind
// ("2 h 30 min", "5'10\""). Returns { base, kind, first, parts } or null.
function quantity(text) {
    const t = String(text || "").trim();
    if (!t) return null;
    // A sum and one unit: "1/2 cup", "(3 + 2) km", "-40 f", "70°F".
    const one = /^([-−+]?[\d\s.,+\-−*×\/÷^%()]*?[\d)%])\s*([^\d\s.,+\-−*×\/÷^%()=][^\d=]*[23]?)$/.exec(t);
    if (one) {
        const v = number(one[1]);
        const u = findUnit(one[2]);
        if (v !== null && u) return { "base": v * u.factor + u.offset, "kind": u.kind, "first": u, "parts": [[v, u]] };
    }
    // A clock: "1:30" is an hour and a half, "1:30 min" a minute and a half.
    const clock = /^(\d+):([0-5]\d)(?::([0-5]\d))?\s*([a-z]*)$/i.exec(t);
    if (clock) {
        const big = clock[4] ? findUnit(clock[4]) : SYMBOL["h"];
        if (!big || (big.symbol !== "h" && big.symbol !== "min") || (clock[3] && big.symbol !== "h")) return null;
        const small = SYMBOL[SMALLER[big.symbol]];
        const parts = [[+clock[1], big], [+clock[2], small]];
        if (clock[3]) parts.push([+clock[3], SYMBOL["s"]]);
        return { "base": parts.reduce((s, p) => s + p[0] * p[1].factor, 0), "kind": "Time", "first": big, "parts": parts };
    }
    // Several parts: "2h30", "2h 30m", "5'10\"", "1m80".
    const re = /(\d+(?:[.,]\d+)?|[.,]\d+)\s*([^\d\s.,][^\d]*?)?\s*(?=\d|$)/y;
    const parts = [];
    let m, prev = null;
    re.lastIndex = 0;
    while (re.lastIndex < t.length && (m = re.exec(t))) {
        const v = parseFloat(m[1].replace(",", "."));
        let u = m[2] ? findUnit(m[2]) : (prev && SYMBOL[SMALLER[prev.symbol]]);
        if (u && prev && prev.kind === "Time" && u.symbol === "m") u = SYMBOL["min"];
        if (!u || (prev && u.kind !== prev.kind) || u.offset) return null;
        parts.push([v, u]);
        prev = u;
    }
    if (parts.length < 2 || re.lastIndex < t.length) return null;
    return { "base": parts.reduce((s, p) => s + p[0] * p[1].factor, 0), "kind": prev.kind, "first": parts[0][1], "parts": parts };
}

function formatUnit(v) {
    if (v === 0 || !isFinite(v)) return String(v === 0 ? 0 : v);
    const a = Math.abs(v);
    if (a >= 1e15 || a < 1e-6) return v.toExponential(4).replace(/\.?0+e/, "e");
    if (a < 1) return String(Number(v.toPrecision(6)));
    const digits = Math.floor(Math.log10(a)) + 1;
    return String(Number(v.toFixed(Math.max(0, 6 - digits))));
}
function withUnit(v, u, exact) { return (exact ? format(v) : formatUnit(v)) + (u.symbol === "°" ? "" : " ") + u.symbol; }
function from(base, u) { return (base - u.offset) / u.factor; }

// "1 d 2 h 30 min" and "5 ft 10.9 in": the same amount in mixed units.
function mixed(q) {
    if (q.kind === "Time" && q.base >= 90 && !(q.parts.length > 1)) {
        let s = Math.round(q.base);
        const out = [];
        for (const [n, u] of [[86400, "d"], [3600, "h"], [60, "min"], [1, "s"]]) {
            const k = Math.floor(s / n);
            if (k) out.push(k + " " + u);
            s -= k * n;
        }
        return out.length > 1 ? out.slice(0, 3).join(" ") : "";
    }
    if (q.kind === "Length" && q.base > 0.3 && q.base < 3) {
        const inches = q.base / 0.0254;
        let ft = Math.floor(inches / 12);
        let rest = Math.round((inches - ft * 12) * 10) / 10;
        if (rest >= 12) { ft++; rest = 0; }
        return ft + " ft" + (rest ? " " + formatUnit(rest) + " in" : "");
    }
    return "";
}

// why (optional) learns why a conversion failed: why.clash = [from, to] when
// both units are known but measure different things ("5 km in kg").
function units(input, why) {
    let s = String(input || "").trim();
    if (s.startsWith("=")) s = s.slice(1).trim();
    if (!s || s.length > 120 || !/^[-−+]?[\d.,(]/.test(s) || !/[a-zµ°º'"′″]/i.test(s)) return null;
    s = s.replace(/\s*(->|→|=>|=)\s*/g, " to ");
    const words = s.split(/\s+/);
    let q = null, to = null;
    // The last "in" or "to" that leaves a unit after it and a quantity before
    // it ("5 in in cm").
    for (let i = words.length - 2; i >= 1 && !to; i--) {
        if (!/^(in|to|into|as|en|a)$/i.test(words[i])) continue;
        const u = findUnit(words.slice(i + 1).join(" "));
        const v = u && quantity(words.slice(0, i).join(" "));
        if (v && v.kind !== u.kind && why && !why.clash) why.clash = [v.first, u];
        if (v && (v.kind === u.kind || v.first.symbol === "oz" || u.symbol === "oz")) { q = v; to = u; }
    }
    if (!to) {
        q = quantity(s);
        if (!q) return null;
        to = SYMBOL[COUNTERPART[q.first.symbol]];
        if (!to) return null;
    }
    // Ounces of something you pour are fluid ounces.
    if (q.kind !== to.kind) {
        if (to.symbol === "oz" && q.kind === "Volume") to = SYMBOL["fl oz"];
        else if (q.first.symbol === "oz" && to.kind === "Volume" && q.parts.length === 1) q = quantity(q.parts[0][0] + " fl oz");
        else return null;
    }
    const v = from(q.base, to);
    if (!isFinite(v)) return null;
    const expression = q.parts.map(p => withUnit(p[0], p[1], true)).join(" ");
    const also = [];
    const mix = mixed(q);
    if (mix && mix !== expression) also.push(mix);
    // Readable sizes first (no 500000 cm), then any that fit.
    for (const most of [1e5, 1e9]) {
        for (const sym of ALSO[q.kind] || []) {
            const u = SYMBOL[sym];
            if (also.length >= 3 || u === to || q.parts.some(p => p[1] === u)) continue;
            const x = from(q.base, u);
            const t = withUnit(x, u);
            if (Math.abs(x) >= 0.01 && Math.abs(x) < most && also.indexOf(t) < 0) also.push(t);
        }
    }
    return { "expression": expression, "value": v, "number": formatUnit(v), "text": withUnit(v, to), "kind": q.kind, "also": also };
}

// ---- Emoji: names first, then CLDR's keywords. Each entry carries its
// lowercase name, the name's words and the keywords (see Launcher.loadEmoji).

// A name's last word is what it is ("red heart" is a heart, "heart suit" a
// suit); shorter names win ties.
function emojiWordScore(e, w) {
    if (e.lname === w) return 100;
    let s = 0;
    if (e.nw[e.nw.length - 1] === w) s = 85;
    else if (e.nw.indexOf(w) >= 0) s = 75;
    else if (e.lname.startsWith(w)) s = 65;
    else if (e.nw.some(x => x.startsWith(w))) s = 55;
    else if (e.kw.indexOf(w) >= 0) s = 50;
    else if (w.length > 1 && e.kw.some(x => x.startsWith(w))) s = 35;
    else if (w.length > 2 && e.lname.indexOf(w) >= 0) s = 20;
    return s ? s - Math.min(8, e.lname.length / 4) : 0;
}
// [{e, score}], best first; ties keep Unicode's order. min drops weak matches.
function emoji(list, query, limit, min) {
    const q = String(query || "").toLowerCase().trim();
    const words = q.split(/\s+/).filter(w => w);
    if (!words.length) return [];
    const out = [];
    for (const e of list) {
        let s = 0;
        if (words.length > 1 && e.lname === q) s = 100;
        else if (words.length > 1 && e.lname.startsWith(q)) s = 90;
        else {
            for (const w of words) {
                const x = emojiWordScore(e, w);
                if (!x) { s = 0; break; }
                s += x / words.length;
            }
        }
        if (s >= (min || 1)) out.push({ "e": e, "score": s });
    }
    out.sort((a, b) => b.score - a.score || a.e.order - b.e.order);
    return out.slice(0, limit || 60);
}
function codepoints(text) {
    const s = String(text || "");
    const out = [];
    for (let i = 0; i < s.length; i++) {
        let c = s.charCodeAt(i);
        const d = i + 1 < s.length ? s.charCodeAt(i + 1) : 0;
        if (c >= 0xd800 && c < 0xdc00 && d >= 0xdc00 && d < 0xe000) { c = (c - 0xd800) * 0x400 + (d - 0xdc00) + 0x10000; i++; }
        out.push("U+" + c.toString(16).toUpperCase().padStart(4, "0"));
    }
    return out.join(" ");
}

// ---- Files

// fd's pattern for a query (a regex on the name, or on the path when the
// query has a "/"): the words in order; one or two letters only at the start
// of a word.
function escapeRegex(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }
function filePattern(q) {
    const words = String(q || "").toLowerCase().split(/\s+/).filter(w => w);
    const body = words.map(escapeRegex).join(".*");
    return q.length < 3 ? "(^|[^a-z0-9])" + body : body;
}
// The same for find (no fd): a glob on the name.
function fileGlob(q) {
    const words = String(q || "").toLowerCase().split(/\s+/).filter(w => w).map(w => w.replace(/[*?[\]\\]/g, "?"));
    return (q.length < 3 ? "" : "*") + words.join("*") + "*";
}
// Does a name still match a longer query (results of the last search stay
// while the next one runs)?
function fileMatches(path, name, q) {
    const hay = (q.indexOf("/") >= 0 ? path : name).toLowerCase();
    let at = 0;
    for (const w of q.split(/\s+/).filter(w => w)) {
        const i = hay.indexOf(w, at);
        if (i < 0) return false;
        at = i + w.length;
    }
    return true;
}
// Name match, then how recently it changed, then how deep it is.
function fileScore(f, q, now) {
    const name = f.name.toLowerCase();
    const dot = f.dir ? -1 : name.lastIndexOf(".");
    const stem = dot > 0 ? name.slice(0, dot) : name;
    const parts = f.name.replace(/([a-z])([A-Z])/g, "$1 $2").toLowerCase().split(/[\s._\-()[\],]+/);
    let s;
    if (stem === q || name === q) s = 100;
    else if (name.startsWith(q)) s = 80;
    else if (parts.some(w => w.startsWith(q))) s = 62;
    else if (name.indexOf(q) >= 0) s = 45;
    else s = 30;
    const days = (now - f.mtime * 1000) / 86400000;
    s += days < 1 ? 18 : days < 7 ? 12 : days < 30 ? 7 : days < 365 ? 2 : 0;
    s -= Math.min(12, 2 * Math.max(0, f.depth - 2));
    if (f.dir) s += 3;
    return s;
}
function fileType(name, dir) {
    if (dir) return { "glyph": "folder", "label": "Folder", "preview": "" };
    const dot = name.lastIndexOf(".");
    const ext = dot > 0 ? name.slice(dot + 1).toLowerCase() : "";
    const is = list => list.indexOf(ext) >= 0;
    if (is(["png", "jpg", "jpeg", "gif", "bmp", "svg", "ico"])) return { "glyph": "image", "label": "Image", "preview": "image", "ext": ext };
    if (is(["webp", "avif", "heic", "tif", "tiff", "raw", "cr2", "nef", "dng", "xcf", "psd", "kra"])) return { "glyph": "image", "label": "Image", "preview": "", "ext": ext };
    if (is(["txt", "md", "markdown", "rst", "org", "log", "csv", "tsv", "tex"])) return { "glyph": "note", "label": "Text", "preview": "text", "ext": ext };
    if (is(["json", "jsonc", "yaml", "yml", "toml", "ini", "conf", "cfg", "nix", "qml", "js", "mjs", "ts", "tsx", "jsx", "py", "rb", "rs", "go", "c", "h", "cc", "cpp", "hpp", "java", "kt", "swift", "sh", "bash", "zsh", "fish", "lua", "sql", "css", "scss", "html", "htm", "xml", "kdl", "el", "vim", "dart", "php", "r", "zig", "frag", "vert", "glsl", "diff", "patch"]))
        return { "glyph": "code", "label": "Code", "preview": "text", "ext": ext };
    if (is(["pdf"])) return { "glyph": "note", "label": "PDF", "preview": "", "ext": ext };
    if (is(["doc", "docx", "odt", "rtf", "pages", "epub"])) return { "glyph": "note", "label": "Document", "preview": "", "ext": ext };
    if (is(["xls", "xlsx", "ods", "numbers"])) return { "glyph": "grid", "label": "Spreadsheet", "preview": "", "ext": ext };
    if (is(["ppt", "pptx", "odp", "key"])) return { "glyph": "display", "label": "Presentation", "preview": "", "ext": ext };
    if (is(["mp3", "flac", "ogg", "oga", "opus", "wav", "m4a", "aac"])) return { "glyph": "music", "label": "Audio", "preview": "", "ext": ext };
    if (is(["mp4", "mkv", "webm", "mov", "avi", "m4v"])) return { "glyph": "play", "label": "Video", "preview": "", "ext": ext };
    if (is(["zip", "tar", "gz", "tgz", "xz", "zst", "bz2", "7z", "rar"])) return { "glyph": "drive", "label": "Archive", "preview": "", "ext": ext };
    if (is(["iso", "img", "qcow2"])) return { "glyph": "drive", "label": "Disk image", "preview": "", "ext": ext };
    if (is(["ttf", "otf", "woff", "woff2"])) return { "glyph": "pencil", "label": "Font", "preview": "", "ext": ext };
    return { "glyph": "note", "label": "File", "preview": "", "ext": ext };
}
function tilde(path, home) { return home && (path === home || path.startsWith(home + "/")) ? "~" + path.slice(home.length) : path; }
// Sizes as file managers show them (powers of 1000).
function bytes(n) {
    if (n < 1000) return n + " B";
    const u = ["kB", "MB", "GB", "TB"];
    let i = -1;
    do { n /= 1000; i++; } while (n >= 1000 && i < u.length - 1);
    return (n < 10 ? n.toFixed(1) : Math.round(n)) + " " + u[i];
}
