/*
 * Folio runtime for workshop studies (classic script; defines window.Folio).
 *
 * The motion language is a printmaker's:
 *   develop  - ink dots arrive in random order, like a print in the tray
 *   dissolve - one plate becomes another dot by dot
 *   bleed    - a new ink or mode spreads from the cursor with a ragged edge
 *   breathe  - the plate's dither keeps moving, in a seamless 2.7 s loop
 *   leaf     - panels turn in from their spine (folio.css)
 *   cascade  - a panel's contents follow it in, 34 ms apart (folio.css)
 *   stamp    - a pressed control sinks and prints a ring (folio.css)
 *
 * Plates are Folio's 1-bit masks (white = paper). The renderer re-dithers
 * them at screen resolution, so any plate prints in any ink at any size, the
 * way a QML ShaderEffect on the real desktop would.
 */
(() => {
  "use strict";
  const KIT = new URL(".", document.currentScript.src).href;
  const INKS = { azure: { light: "#214c94", dark: "#adc7ed" }, cobalt: { light: "#244fb8", dark: "#9dbbfa" }, slate: { light: "#35556e", dark: "#adc3d2" } };
  const PAPER = { light: "#f7f4e9", dark: "#101d33" };
  const BLEED_MS = 950;
  const NS = "http://www.w3.org/2000/svg";
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const root = document.documentElement;
  const state = { mode: root.dataset.mode || "light", ink: root.dataset.ink || "azure" };
  root.dataset.mode = state.mode;
  root.dataset.ink = state.ink;
  const listeners = new Set();

  const rgb = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
  const palette = (s = state) => ({ paper: PAPER[s.mode], ink: INKS[s.ink][s.mode] });
  const mixHex = (a, b, t) => "#" + rgb(a).map((v, i) => Math.round((v + (rgb(b)[i] - v) * t) * 255).toString(16).padStart(2, "0")).join("");
  // Plates in dark mode. "moonlit" keeps the picture's tones: its light areas
  // print in a softened ink on night, its shadows stay dark, and a fifth of the
  // light dots are thinned so large skies do not glare. "negative" is Folio's
  // original dark plate: ink areas printed light, which reads as a negative.
  const plateStyle = { dark: "moonlit" };
  const platePalette = (s = state) => {
    const base = palette(s);
    if (s.mode !== "dark" || plateStyle.dark === "negative") return { ...base, invert: 0, thin: 0 };
    return { paper: base.paper, ink: mixHex(base.ink, base.paper, 0.22), invert: 1, thin: 0.2 };
  };

  function bezier(x1, y1, x2, y2) {
    const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
    const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
    const sx = (t) => ((ax * t + bx) * t + cx) * t, sy = (t) => ((ay * t + by) * t + cy) * t;
    const dx = (t) => (3 * ax * t + 2 * bx) * t + cx;
    return (x) => {
      let t = x;
      for (let i = 0; i < 8; i++) {
        const e = sx(t) - x, d = dx(t);
        if (Math.abs(e) < 1e-5 || !d) break;
        t -= e / d;
      }
      return sy(Math.min(1, Math.max(0, t)));
    };
  }
  const EASE = bezier(0.2, 0, 0, 1);
  const LINEAR = (t) => t;
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));

  function tween(duration, fn, curve = EASE) {
    return new Promise((resolve) => {
      if (reduced || duration <= 0) { fn(1); resolve(); return; }
      const start = performance.now();
      const step = (now) => {
        const t = Math.min(1, (now - start) / duration);
        fn(curve(t));
        if (t < 1) requestAnimationFrame(step); else resolve();
      };
      requestAnimationFrame(step);
    });
  }

  // ---------------------------------------------------------------- icons

  const ICONS = {
    wifi: '<path d="M2.5 9a14 14 0 0 1 19 0M5.5 12.5a9.5 9.5 0 0 1 13 0M8.5 16a5 5 0 0 1 7 0"/><circle cx="12" cy="19.3" r="1.2" fill="currentColor" stroke="none"/>',
    bluetooth: '<path d="M7 7.5l10 9.5-5 4.5V2.5l5 4.5-10 9.5"/>',
    moon: '<path d="M19.5 14.6A8 8 0 1 1 9.4 4.5a6.5 6.5 0 0 0 10.1 10.1z"/>',
    sun: '<circle cx="12" cy="12" r="3.8"/><path d="M12 2.8v2M12 19.2v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2.8 12h2M19.2 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
    cup: '<path d="M4.5 9.5h11v4.5a5 5 0 0 1-5 5h-1a5 5 0 0 1-5-5zM15.5 10.5h1.5a2.5 2.5 0 0 1 0 5h-1.5M8 3.5c0 1.2 1 1.3 1 2.6M12 3.5c0 1.2 1 1.3 1 2.6"/>',
    speaker: '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z"/><path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11"/>',
    battery: '<rect x="2.5" y="7" width="17" height="10" rx="2.8"/><path d="M21.5 10.5v3"/><rect x="5" y="9.5" width="9" height="5" rx="1.2" fill="currentColor" stroke="none"/>',
    power: '<path d="M12 3v8.5M6.6 6.6a7.6 7.6 0 1 0 10.8 0"/>',
    gear: '<circle cx="12" cy="12" r="3"/><circle cx="12" cy="12" r="7"/><path d="M12 2.5V5M12 19v2.5M21.5 12H19M5 12H2.5M18.7 5.3L17 7M7 17l-1.7 1.7M18.7 18.7L17 17M7 7L5.3 5.3"/>',
    bell: '<path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0"/>',
    search: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/>',
    play: '<path d="M8 5.5v13l10.5-6.5z" fill="currentColor"/>',
    pause: '<path d="M8.5 5.5v13M15.5 5.5v13" stroke-width="2.6"/>',
    next: '<path d="M6 6.5l8 5.5-8 5.5zM18 6v12" fill="currentColor"/>',
    prev: '<path d="M18 6.5l-8 5.5 8 5.5zM6 6v12" fill="currentColor"/>',
    folder: '<path d="M3 7.5a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/>',
    globe: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.4 2.6 3.4 5.4 3.4 8.5s-1 5.9-3.4 8.5c-2.4-2.6-3.4-5.4-3.4-8.5s1-5.9 3.4-8.5z"/>',
    terminal: '<path d="M5.5 8l4 4-4 4M12 16h6.5"/>',
    mail: '<rect x="3" y="5.5" width="18" height="13" rx="2.2"/><path d="M3.5 7.5l8.5 6 8.5-6"/>',
    music: '<path d="M9 17.5V6.2l10-2.2v11.5"/><circle cx="6.5" cy="17.5" r="2.5"/><circle cx="16.5" cy="15.5" r="2.5"/>',
    message: '<path d="M4 6.5A2.5 2.5 0 0 1 6.5 4h11A2.5 2.5 0 0 1 20 6.5v8a2.5 2.5 0 0 1-2.5 2.5H10l-4.5 3.5V17A2.5 2.5 0 0 1 4 14.5z"/>',
    note: '<path d="M6 3.5h8.5l3.5 3.5v13.5H6zM9 10.5h6M9 14h6M9 17.5h3.5"/>',
    image: '<rect x="3.5" y="4.5" width="17" height="15" rx="2.2"/><circle cx="9" cy="10" r="1.8"/><path d="M4 17.5l5-4.5 4 3.5 3-2.5 4 3.5"/>',
    lock: '<rect x="5" y="10.5" width="14" height="10" rx="2.5"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/>',
    user: '<circle cx="12" cy="8.5" r="3.5"/><path d="M5 20a7 7 0 0 1 14 0"/>',
    fingerprint: '<path d="M7.6 18.6c1-2 1.4-4 1.4-6.6a3 3 0 0 1 6 0c0 3-.5 5.5-1.5 7.5M12 12c0 3.4-.8 6-2 8M18 15c.3-1 .5-2 .5-3a6.5 6.5 0 0 0-11.7-3.9M5.5 15.5c.3-1 .5-2.2.5-3.5"/>',
    eye: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
    right: '<path d="M9.5 6l6 6-6 6"/>',
    down: '<path d="M6 9.5l6 6 6-6"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
    close: '<path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/>',
    sidebar: '<rect x="3.5" y="4.5" width="17" height="15" rx="2.5"/><path d="M14.5 4.5v15"/>',
    display: '<rect x="3" y="4.5" width="18" height="12" rx="2"/><path d="M9 20h6M12 16.5V20"/>',
    palette: '<path d="M12 3.5a8.5 8.5 0 1 0 0 17c1.3 0 1.9-1 1.4-2.2-.6-1.4.4-2.8 1.9-2.8H17a3.5 3.5 0 0 0 3.5-3.5c0-4.7-3.8-8.5-8.5-8.5z"/><circle cx="7.8" cy="11.5" r="1.1" fill="currentColor" stroke="none"/><circle cx="10.5" cy="7.5" r="1.1" fill="currentColor" stroke="none"/><circle cx="15" cy="7.8" r="1.1" fill="currentColor" stroke="none"/>',
    keyboard: '<rect x="2.5" y="6" width="19" height="12" rx="2.2"/><path d="M6.5 10h.01M10 10h.01M14 10h.01M17.5 10h.01M7.5 14h9"/>',
    sparkle: '<path d="M12 3.5l1.8 5.2 5.2 1.8-5.2 1.8-1.8 5.2-1.8-5.2L5 10.5l5.2-1.8z"/><path d="M18.5 16.5l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7z"/>',
    grid: '<rect x="4" y="4" width="6.5" height="6.5" rx="1.8"/><rect x="13.5" y="4" width="6.5" height="6.5" rx="1.8"/><rect x="4" y="13.5" width="6.5" height="6.5" rx="1.8"/><rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.8"/>',
    calendar: '<rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
    shield: '<path d="M12 3.5l7 3v5c0 4.5-3 7.8-7 9-4-1.2-7-4.5-7-9v-5z"/>',
    arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>',
    mic: '<rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5"/>',
    code: '<path d="M8.5 7.5L4 12l4.5 4.5M15.5 7.5L20 12l-4.5 4.5M13.5 5l-3 14"/>',
    back: '<path d="M14.5 6l-6 6 6 6"/>',
    reload: '<path d="M19.5 12a7.5 7.5 0 1 1-2.2-5.3M19.5 4.5v4h-4"/>',
    star: '<path d="M12 4l2.4 5 5.4.6-4 3.7 1.1 5.3L12 16l-4.9 2.6 1.1-5.3-4-3.7 5.4-.6z"/>',
    camera: '<rect x="3" y="7" width="12.5" height="10" rx="2.5"/><path d="M15.5 10.5l5-3v9l-5-3"/>',
    bolt: '<path d="M13 3L5.5 13.5H11L10 21l7.5-10.5H12z"/>',
    mute: '<path d="M4 9.5h3.5L12 5.5v13l-4.5-4H4z"/><path d="M16 9.5l5 5M21 9.5l-5 5"/>',
    screen: '<rect x="3" y="4.5" width="18" height="12" rx="2"/><path d="M9 20h6M12 16.5V20"/><circle cx="12" cy="10.5" r="2" fill="currentColor" stroke="none"/>',
    mouse: '<rect x="6.5" y="3" width="11" height="18" rx="5.5"/><path d="M12 3v6.5M6.5 9.5h11"/>',
    touchpad: '<rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="M3 15h18M12 15v4.5"/>',
    info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.5M12 7.6v.01"/>',
    apps: '<circle cx="7" cy="7" r="2.6"/><circle cx="17" cy="7" r="2.6"/><circle cx="7" cy="17" r="2.6"/><circle cx="17" cy="17" r="2.6"/>',
    drive: '<rect x="3" y="7.5" width="18" height="9" rx="2.2"/><path d="M6.5 12h.01M9.5 12h.01M14.5 12h3.5"/>',
    usb: '<path d="M9 3.5h6v5H9zM7.5 8.5h9v7a4.5 4.5 0 0 1-9 0zM12 20v1.5M10.5 5.8h.01M13.5 5.8h.01"/>',
    eject: '<path d="M5 14h14L12 6z"/><path d="M5 18h14"/>',
    headphones: '<path d="M4.5 16v-3.5a7.5 7.5 0 0 1 15 0V16"/><rect x="3.5" y="14" width="4" height="6" rx="1.6"/><rect x="16.5" y="14" width="4" height="6" rx="1.6"/>',
    ethernet: '<rect x="4.5" y="4.5" width="15" height="15" rx="2.5"/><path d="M8.5 14.5v2.5M12 14.5v2.5M15.5 14.5v2.5M8 14.5h8V10h-2V8h-4v2H8z"/>',
    laptop: '<rect x="5" y="5" width="14" height="10" rx="1.6"/><path d="M2.5 18.5h19"/>',
    pencil: '<path d="M15.5 4.5l4 4L9 19H5v-4z"/><path d="M13.5 6.5l4 4"/>',
    minus: '<path d="M5 12h14"/>',
    trash: '<path d="M4.5 6.5h15M9.5 6.5V4.5h5v2M6.5 6.5l1 13h9l1-13M10 10v6.5M14 10v6.5"/>',
    chip: '<rect x="6.5" y="6.5" width="11" height="11" rx="2"/><path d="M9.5 3v3.5M14.5 3v3.5M9.5 17.5V21M14.5 17.5V21M3 9.5h3.5M3 14.5h3.5M17.5 9.5H21M17.5 14.5H21"/>',
    link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1.2 1.2M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1.2-1.2"/>',
  };
  let sprite;
  function ensureSprite() {
    if (sprite) return;
    sprite = document.createElementNS(NS, "svg");
    sprite.setAttribute("aria-hidden", "true");
    sprite.style.cssText = "position:absolute;width:0;height:0;overflow:hidden";
    sprite.innerHTML = Object.entries(ICONS).map(([n, d]) => `<symbol id="fi-${n}" viewBox="0 0 24 24">${d}</symbol>`).join("") + "<defs></defs>";
    document.body.prepend(sprite);
  }
  const icon = (name, cls = "") => `<svg class="i ${cls}" viewBox="0 0 24 24" aria-hidden="true"><use href="#fi-${name}"/></svg>`;

  // ------------------------------------------------- develop (DOM elements)

  // An SVG filter thresholds pixel-scale noise against a moving level, so an
  // element prints in (or lifts off) dot by dot, like the plates.
  let filterCount = 0;
  function develop(el, { duration = 700, reverse = false, grain = 0.8, keep = false } = {}) {
    if (!el || reduced) return Promise.resolve();
    ensureSprite();
    const id = `folio-develop-${++filterCount}`;
    const filter = document.createElementNS(NS, "filter");
    filter.id = id;
    for (const [k, v] of Object.entries({ x: "-5%", y: "-5%", width: "110%", height: "110%", "color-interpolation-filters": "sRGB" })) filter.setAttribute(k, v);
    filter.innerHTML = `<feTurbulence type="fractalNoise" baseFrequency="${grain}" numOctaves="1" seed="${filterCount % 97}" result="n"/>
      <feColorMatrix in="n" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  1 0 0 0 0" result="a"/>
      <feComponentTransfer in="a" result="m"><feFuncA type="linear" slope="30" intercept="-27"/></feComponentTransfer>
      <feComposite in="SourceGraphic" in2="m" operator="in"/>`;
    sprite.querySelector("defs").append(filter);
    const fn = filter.querySelector("feFuncA");
    el.style.filter = `url(#${id})`;
    return tween(duration, (p) => {
      const v = reverse ? 1 - p : p;
      fn.setAttribute("intercept", String(-27 + v * 25));
    }, LINEAR).then(() => {
      if (!keep) { el.style.filter = ""; filter.remove(); }
    });
  }

  // ------------------------------------------------------- small motions

  function cascade(el, delay) {
    [...el.children].forEach((child, i) => child.style.setProperty("--i", i));
    if (delay !== undefined) el.style.setProperty("--cascade-delay", `${delay}ms`);
    el.classList.remove("cascade");
    void el.offsetWidth;
    el.classList.add("cascade");
  }

  function stamps(scope = document) {
    scope.addEventListener("pointerdown", (e) => {
      const target = e.target.closest(".stamp");
      if (!target) return;
      const ring = document.createElement("span");
      ring.className = "stamp-ring";
      target.append(ring);
      ring.addEventListener("animationend", () => ring.remove());
    });
  }

  function seg(el, onChange) {
    let thumb = el.querySelector(".thumb");
    if (!thumb) { thumb = document.createElement("span"); thumb.className = "thumb"; el.prepend(thumb); }
    const place = () => {
      const on = el.querySelector('[aria-pressed="true"]');
      if (!on) return;
      thumb.style.left = `${on.offsetLeft}px`;
      thumb.style.width = `${on.offsetWidth}px`;
    };
    el.addEventListener("click", (e) => {
      const b = e.target.closest("button");
      if (!b || b.getAttribute("aria-pressed") === "true") return;
      el.querySelectorAll("button").forEach((x) => x.setAttribute("aria-pressed", x === b));
      place();
      onChange?.(b.dataset.value, e);
    });
    new ResizeObserver(place).observe(el);
    place();
    return place;
  }

  function range(input) {
    const paint = () => input.style.setProperty("--fill", `${((input.value - input.min) / (input.max - input.min)) * 100}%`);
    input.addEventListener("input", paint);
    paint();
  }

  // ------------------------------------------------------ theme (mode, ink)

  function set(next, origin) {
    const prev = { ...state };
    Object.assign(state, next);
    if (prev.mode === state.mode && prev.ink === state.ink) return;
    const o = origin && origin.clientX !== undefined ? { x: origin.clientX, y: origin.clientY } : origin || { x: innerWidth / 2, y: innerHeight / 2 };
    const radius = Math.hypot(Math.max(o.x, innerWidth - o.x), Math.max(o.y, innerHeight - o.y));
    const apply = () => {
      root.dataset.mode = state.mode;
      root.dataset.ink = state.ink;
      listeners.forEach((fn) => fn(state, prev, o, radius));
    };
    if (!document.startViewTransition || reduced) { apply(); return; }
    const vt = document.startViewTransition(apply);
    vt.ready.then(() => root.animate(
      { clipPath: [`circle(0px at ${o.x}px ${o.y}px)`, `circle(${radius}px at ${o.x}px ${o.y}px)`] },
      { duration: BLEED_MS, easing: "cubic-bezier(0.2, 0, 0, 1)", pseudoElement: "::view-transition-new(root)" },
    )).catch(() => {});
  }

  // ------------------------------------------------------------ plates

  const VS = `#version 300 es
in vec2 p;
void main() { gl_Position = vec4(p, 0.0, 1.0); }`;

  const FS = `#version 300 es
precision highp float;
uniform sampler2D uA, uB;
uniform vec2 uRes, uSizeA, uSizeB, uFocusA, uFocusB, uOrigin;
uniform vec3 uPaper0, uInk0, uPaper1, uInk1;
uniform float uDot, uMix, uDevelop, uRadius, uEdge, uTime, uBreathe, uZoomA, uZoomB, uLift;
uniform vec2 uInvert, uThin;
out vec4 o;

float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }
float hash(vec2 p) { vec3 q = fract(vec3(p.xyx) * 0.1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }

// object-fit: cover around the plate's focus point; span is the visible part.
vec2 cover(vec2 uv, vec2 size, vec2 focus, float zoom, out vec2 span) {
  float sr = uRes.x / uRes.y, tr = size.x / size.y;
  span = (sr > tr ? vec2(1.0, tr / sr) : vec2(sr / tr, 1.0)) / zoom;
  vec2 off = clamp(focus - span * 0.5, vec2(0.0), vec2(1.0) - span);
  return off + uv * span;
}

// Near native size the plate prints its own Atkinson dots; smaller, it is
// re-dithered from local tone with a little extra contrast, as Atkinson has.
float coverage(sampler2D t, vec2 uv, vec2 size, float lod) {
  if (lod < 0.75) return 1.0 - texelFetch(t, ivec2(clamp(uv, 0.0, 0.9999) * size), 0).r;
  return smoothstep(0.1, 0.9, 1.0 - textureLod(t, uv, lod).r);
}

void main() {
  vec2 cell = floor(gl_FragCoord.xy / uDot);
  vec2 px = (cell + 0.5) * uDot;
  vec2 uv = vec2(px.x / uRes.x, 1.0 - px.y / uRes.y);

  // Breathe: the whole plate keeps re-printing itself. Every live dot takes
  // its threshold from a loop of 24 noise frames at 9 fps (2.7 s), so the
  // dither moves evenly everywhere and repeats seamlessly. uBreathe is the
  // share of dots that are alive.
  float live = step(hash(cell + 41.7), uBreathe);
  float frame = mod(floor(uTime * 9.0), 24.0);
  float th = ign(cell + live * frame * vec2(17.0, 31.0));

  vec2 spanA, spanB;
  vec2 uvA = cover(uv, uSizeA, uFocusA, uZoomA, spanA);
  vec2 uvB = cover(uv, uSizeB, uFocusB, uZoomB, spanB);
  float lodA = log2(max(1.0, uSizeA.x * spanA.x / uRes.x * uDot));
  float lodB = log2(max(1.0, uSizeB.x * spanB.x / uRes.x * uDot));
  // Live dots print from local tone, so they can move; still dots keep the
  // plate's own Atkinson pattern.
  if (live > 0.5) { lodA = max(lodA, 1.2); lodB = max(lodB, 1.2); }
  float covA = clamp(coverage(uA, uvA, uSizeA, lodA) - uLift, 0.0, 1.0);
  float covB = clamp(coverage(uB, uvB, uSizeB, lodB) - uLift, 0.0, 1.0);
  vec2 fromTop = vec2(px.x, uRes.y - px.y);
  float reach = distance(fromTop, uOrigin) + (hash(cell + 9.7) - 0.5) * uEdge;
  float fresh = step(reach, uRadius);
  vec3 paper = mix(uPaper0, uPaper1, fresh);
  vec3 inkc = mix(uInk0, uInk1, fresh);
  float invert = mix(uInvert.x, uInvert.y, fresh);
  float thin = mix(uThin.x, uThin.y, fresh);

  // Normal plates print the picture's ink; moonlit ones print its paper,
  // thinned through the same ordered threshold so skies stay even, not grainy.
  float sel = step(hash(cell + 3.1), uMix);
  float inkA = step(th, covA) * step(0.002, covA);
  float inkB = step(th, covB) * step(0.002, covB);
  float moonA = step(th, (1.0 - covA) * (1.0 - thin)) * step(0.002, 1.0 - covA);
  float moonB = step(th, (1.0 - covB) * (1.0 - thin)) * step(0.002, 1.0 - covB);
  float lit = mix(mix(inkA, inkB, sel), mix(moonA, moonB, sel), invert);
  lit *= step(hash(cell + 17.3), uDevelop);
  o = vec4(mix(paper, inkc, lit), 1.0);
}`;

  const plates = new Set();
  const textures = new Map();
  let catalog;

  async function loadCatalog() {
    if (!catalog) catalog = fetch(new URL("plates.json", KIT)).then((r) => r.json());
    return catalog;
  }
  async function plateInfo(id) {
    const cat = await loadCatalog();
    for (const c of cat.collections) for (const p of c.plates) if (p.id === id) return { ...p, collection: c };
    throw new Error(`no plate ${id}`);
  }
  function loadImage(url) {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => reject(new Error(`could not load ${url}`));
      img.src = url;
    });
  }

  // A renderer is one WebGL context with the plate program and a texture
  // cache. Browsers allow about sixteen contexts per page, so only living
  // (breathing) plates get their own; every other plate shares one renderer
  // and copies its frame into a plain 2D canvas.
  function makeRenderer(canvas) {
    const gl = canvas.getContext("webgl2", { antialias: false, alpha: false, preserveDrawingBuffer: false });
    if (!gl) return null;
    const sh = (type, src) => {
        const s = gl.createShader(type);
        gl.shaderSource(s, src);
        gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
      return s;
    };
    const prog = gl.createProgram();
    gl.attachShader(prog, sh(gl.VERTEX_SHADER, VS));
    gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, FS));
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog));
    gl.useProgram(prog);
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(prog, "p");
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
    const u = {};
    for (const name of ["uA", "uB", "uRes", "uSizeA", "uSizeB", "uFocusA", "uFocusB", "uOrigin", "uPaper0", "uInk0", "uPaper1", "uInk1",
      "uDot", "uMix", "uDevelop", "uRadius", "uEdge", "uTime", "uBreathe", "uZoomA", "uZoomB", "uLift", "uInvert", "uThin"]) u[name] = gl.getUniformLocation(prog, name);
    gl.uniform1i(u.uA, 0);
    gl.uniform1i(u.uB, 1);
    return { gl, u, canvas, textures: new Map() };
  }
  let sharedRenderer;
  const shared = () => {
    if (!sharedRenderer) { const c = document.createElement("canvas"); c.width = c.height = 1; sharedRenderer = makeRenderer(c); }
    return sharedRenderer;
  };

  class Plate {
    // mode pins a plate to light or dark whatever the desktop's mode, for
    // previews such as the mode cards in Appearance. own gives the plate its
    // own WebGL context; breathing plates always have one.
    constructor(canvas, { plate, breathe = 0, dot = 1, zoom = 1, develop: dev = true, edge = 90, lift = 0, mode = null, own } = {}) {
      this.canvas = canvas;
      this.opts = { breathe, dot, zoom, edge, lift, mode };
      this.own = own ?? breathe > 0;
      this.r = this.own ? makeRenderer(canvas) : shared();
      this.ctx = this.own ? null : canvas.getContext("2d");
      this.gl = this.r?.gl;
      if (!this.gl) { canvas.style.background = "var(--wash)"; return; }
      this.u = this.r.u;
      this.v = { mix: 0, develop: dev ? 0 : 1, radius: 1e7, origin: [0, 0], zoomA: zoom, zoomB: zoom };
      this.c0 = this.c1 = this.palette();
      this.a = this.b = null;
      this.t0 = performance.now();
      this.dirty = true;
      new ResizeObserver(() => this.resize()).observe(canvas);
      this.resize();
      listeners.add((s, prev, o, radius) => this.bleed(o, radius));
      plates.add(this);
      tick();
      if (plate) this.ready = this.show(plate, { develop: dev });
    }

    palette() { return platePalette(this.opts.mode ? { ...state, mode: this.opts.mode } : state); }

    resize() {
      const dpr = devicePixelRatio || 1;
      const w = Math.max(1, Math.round(this.canvas.clientWidth * dpr)), h = Math.max(1, Math.round(this.canvas.clientHeight * dpr));
      if (this.canvas.width !== w || this.canvas.height !== h) { this.canvas.width = w; this.canvas.height = h; this.dirty = true; }
    }

    async texture(id) {
      if (!textures.has(id)) {
        textures.set(id, (async () => {
          const info = await plateInfo(id);
          const img = await loadImage(new URL(info.file, KIT));
          return { img, info };
        })());
      }
      const { img, info } = await textures.get(id);
      const gl = this.gl;
      const cache = this.r.textures;
      if (!cache.has(id)) {
        const t = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, t);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.R8, gl.RED, gl.UNSIGNED_BYTE, img);
        gl.generateMipmap(gl.TEXTURE_2D);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        cache.set(id, { tex: t, size: [img.width, img.height], focus: info.focus, info });
      }
      return cache.get(id);
    }

    // Show a plate: develop it from paper the first time, dissolve to it after.
    async show(id, { develop: dev = true, duration } = {}) {
      if (!this.gl) return;
      const t = await this.texture(id);
      this.info = t.info;
      if (!this.a) {
        this.a = t;
        this.dirty = true;
        if (dev) await tween(duration || 1400, (p) => { this.v.develop = p; this.dirty = true; }, bezier(0.4, 0, 0.2, 1));
        else this.v.develop = 1;
        return;
      }
      if (this.a === t) return;
      this.b = t;
      await tween(duration || 1200, (p) => { this.v.mix = p; this.dirty = true; }, bezier(0.4, 0, 0.2, 1));
      this.a = t;
      this.b = null;
      this.v.mix = 0;
      this.dirty = true;
    }

    // Re-develop the current plate from paper (or lift it off with reverse).
    develop({ duration = 1400, reverse = false } = {}) {
      return tween(duration, (p) => { this.v.develop = reverse ? 1 - p : p; this.dirty = true; }, bezier(0.4, 0, 0.2, 1));
    }

    zoom(to, duration = 900) {
      const from = this.v.zoomA;
      return tween(duration, (p) => { this.v.zoomA = this.v.zoomB = from + (to - from) * p; this.dirty = true; });
    }

    lift(to, duration = 600) {
      const from = this.opts.lift;
      return tween(duration, (p) => { this.opts.lift = from + (to - from) * p; this.dirty = true; });
    }

    bleed(o, radius) {
      if (!this.gl) return;
      const r = this.canvas.getBoundingClientRect();
      this.v.origin = [o.x - r.left, o.y - r.top];
      this.c1 = this.palette();
      const edge = this.opts.edge;
      // The view transition's circle reaches `radius` in BLEED_MS; the plate's
      // ragged edge rides just inside it, so ink soaks in behind the reveal.
      tween(BLEED_MS, (p) => { this.v.radius = p * radius - edge * 0.5 * (1 - p); this.dirty = true; }).then(() => {
        this.c0 = this.c1;
        this.v.radius = 1e7;
        this.dirty = true;
      });
      this.v.radius = -edge;
    }

    render(now) {
      const gl = this.gl;
      if (!gl || !this.a) return;
      const animated = this.opts.breathe > 0;
      if (!this.dirty && !animated) return;
      this.dirty = false;
      const dpr = devicePixelRatio || 1;
      const W = this.canvas.width, H = this.canvas.height;
      if (!this.own) {
        // Grow the shared canvas only; draw into its bottom-left corner.
        const sc = this.r.canvas;
        if (sc.width < W) sc.width = W;
        if (sc.height < H) sc.height = H;
      }
      gl.viewport(0, 0, W, H);
      const b = this.b || this.a;
      gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, this.a.tex);
      gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, b.tex);
      gl.uniform2f(this.u.uRes, this.canvas.width, this.canvas.height);
      gl.uniform2f(this.u.uSizeA, ...this.a.size);
      gl.uniform2f(this.u.uSizeB, ...b.size);
      gl.uniform2f(this.u.uFocusA, ...this.a.focus);
      gl.uniform2f(this.u.uFocusB, ...b.focus);
      gl.uniform2f(this.u.uOrigin, this.v.origin[0] * dpr, this.v.origin[1] * dpr);
      gl.uniform3f(this.u.uPaper0, ...rgb(this.c0.paper));
      gl.uniform3f(this.u.uInk0, ...rgb(this.c0.ink));
      gl.uniform3f(this.u.uPaper1, ...rgb(this.c1.paper));
      gl.uniform3f(this.u.uInk1, ...rgb(this.c1.ink));
      gl.uniform1f(this.u.uDot, Math.max(1, Math.round(dpr * this.opts.dot)));
      gl.uniform1f(this.u.uMix, this.v.mix);
      gl.uniform1f(this.u.uDevelop, this.v.develop);
      gl.uniform1f(this.u.uRadius, this.v.radius * dpr);
      gl.uniform1f(this.u.uEdge, this.opts.edge * dpr);
      gl.uniform1f(this.u.uTime, (now - this.t0) / 1000);
      gl.uniform1f(this.u.uBreathe, this.opts.breathe);
      gl.uniform1f(this.u.uZoomA, this.v.zoomA);
      gl.uniform1f(this.u.uZoomB, this.v.zoomB);
      gl.uniform1f(this.u.uLift, this.opts.lift);
      gl.uniform2f(this.u.uInvert, this.c0.invert, this.c1.invert);
      gl.uniform2f(this.u.uThin, this.c0.thin, this.c1.thin);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      if (!this.own) this.ctx.drawImage(this.r.canvas, 0, this.r.canvas.height - H, W, H, 0, 0, W, H);
    }
  }

  let ticking = false;
  function tick() {
    if (ticking) return;
    ticking = true;
    const frame = (now) => {
      for (const p of plates) if (p.canvas.isConnected) p.render(now);
      requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  }

  // Marquee: glides a single line back and forth only when it overflows,
  // at a reading pace, pausing at each end. Re-measures on resize and when
  // the text changes (call again).
  const marquees = new WeakMap();
  function marquee(el, text) {
    if (text !== undefined) el.textContent = text;
    let span = el.firstElementChild;
    if (!span || span.tagName !== "SPAN" || el.childNodes.length !== 1) {
      span = document.createElement("span");
      span.textContent = el.textContent;
      el.textContent = "";
      el.append(span);
    }
    el.classList.add("marquee");
    const measure = () => {
      el.classList.remove("overflowing");
      const over = span.scrollWidth - el.clientWidth;
      if (over > 2) {
        el.style.setProperty("--marquee-x", `${-over - 8}px`);
        el.style.setProperty("--marquee-t", `${Math.max(6, over / 28 + 4)}s`);
        el.classList.add("overflowing");
      }
    };
    if (!marquees.has(el)) { const ro = new ResizeObserver(measure); ro.observe(el); marquees.set(el, ro); }
    requestAnimationFrame(measure);
  }

  // A clock that prints its new minute instead of swapping text.
  function clock(el, format) {
    const render = () => format(new Date());
    let last = "";
    const update = () => {
      const text = render();
      if (text === last) return;
      const first = !last;
      last = text;
      el.textContent = text;
      if (!first) develop(el, { duration: 600 });
    };
    update();
    setInterval(update, 1000);
  }

  document.addEventListener("DOMContentLoaded", () => { ensureSprite(); stamps(); });
  if (document.readyState !== "loading") { ensureSprite(); stamps(); }

  function setDarkPlates(style) {
    plateStyle.dark = style;
    for (const p of plates) {
      p.c0 = p.c1 = p.palette();
      p.dirty = true;
      if ((p.opts.mode || state.mode) === "dark") p.develop({ duration: 900 });
    }
  }

  window.Folio = {
    INKS, PAPER, BLEED_MS, state, palette, platePalette, setDarkPlates, set, on: (fn) => listeners.add(fn),
    icon, develop, cascade, seg, range, clock, marquee, tween, wait, bezier, EASE,
    Plate, plates: loadCatalog, plateInfo, reduced,
  };
})();
