#!/usr/bin/env python3
"""Print Interstellar's Plymouth theme: the art on the left, the page on the right.

One look is a theme (Folio or Lumen), a mode and one color, resolved by
tools/azure-folio/looks.py exactly as the desktop resolves it, and for Lumen
its sky. Folio prints its plate in the derived ink beside a paper page;
Lumen shows its sky (prism, glow or haze, as shaders/lumen.frag draws it)
beside a plain page in the window color.

Everything static is drawn here, with Interstellar's own fonts, icons and
palette, so the disk-unlock screen does not depend on font rendering inside
the initrd. Plymouth only places these images and renders the few strings
that arrive at boot (systemd's prompt, messages, the unit being started).
The page is drawn for 1920x1200, Bonhart's panel and its firmware console;
the art is printed at every listed screen size.

The same code prints the theme built into the initrd (at build time) and the
look the system writes to the boot partition when the owner changes it
(boot_look.py), so both are always drawn alike.
"""
import argparse
import importlib.util
import io
import json
import math
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, features

SHARE = 0.56  # the lock's split: art 56 %, page 44 %

# Interstellar's icons (workshop/studies/_kit/folio.js): 24-unit grid, 1.6 stroke.
ICONS = {
    'laptop': '<rect x="5" y="5" width="14" height="10" rx="1.6"/><path d="M2.5 18.5h19"/>',
    'lock': '<rect x="5" y="10.5" width="14" height="10" rx="2.5"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/>',
    'keyboard': '<rect x="2.5" y="6" width="19" height="12" rx="2.2"/>'
                '<path d="M6.5 10h.01M10 10h.01M14 10h.01M17.5 10h.01M7.5 14h9"/>',
    'check': '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
    'info': '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.5M12 7.6v.01"/>',
    'right': '<path d="M9.5 6l6 6-6 6"/>',
}


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def rgb(value):
    value = value.lstrip('#')
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def luminance(c):
    def channel(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(v) for v in c)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    hi, lo = sorted((luminance(a), luminance(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


# ------------------------------------------------------------------ palettes

def folio_palette(looks, mode, pick):
    """Folio's tokens (dotfiles/quickshell/folio/Common/Theme.qml), in the
    look's ink.

    Secondary text uses Folio's higher-contrast setting: this screen is read
    through the KVM's compressed video capture as often as on the panel.
    """
    dark = mode == 'dark'
    p = {
        'paper': rgb('#101d33' if dark else '#f7f4e9'),
        'text': rgb('#e4e9f0' if dark else '#1a2740'),
        'ink': rgb(looks.derive('folio', mode, pick)[0]),
        'sheet': rgb('#182a49' if dark else '#fffdf6'),
        'shade': rgb('#02060e' if dark else '#101d33'),
        'error': rgb('#f09088' if dark else '#b4473f'),
        'warning': rgb('#e3b267' if dark else '#b07a26'),
    }
    p['success'] = rgb('#8cc5a3') if dark else mix(rgb('#3f7d5c'), p['ink'], 0.2)
    p['text2'] = mix(p['text'], p['paper'], 0.16)
    p['text3'] = mix(p['text'], p['paper'], 0.30)
    # Opaque equivalents of the translucent ink tokens over paper.
    p['well'] = mix(p['paper'], p['ink'], 0.09)
    p['rule'] = mix(p['paper'], p['ink'], 0.16)
    p['ruleStrong'] = mix(p['paper'], p['ink'], 0.30)
    p['sheetStrong'] = p['sheet']
    # What the script calls them: the page, typed dots and the count.
    p['page'] = p['paper']
    p['dot'] = p['ink']
    return p


def lumen_palette(looks, mode, pick):
    """Lumen's tokens (workshop/studies/interstellar/v1.html): neutral grays,
    the window color for the page, the look's accent for the button and the
    caret. Secondary text uses --tx2, not --tx3, for the KVM's capture."""
    dark = mode == 'dark'
    accent, on_accent = looks.derive('lumen', mode, pick)
    named = looks.colors('lumen', mode, pick)
    win = rgb(looks.BACKGROUND['lumen'][mode])
    toward = (255, 255, 255) if dark else (0, 0, 0)
    p = {
        'page': win,
        'text': rgb('#f5f5f7' if dark else '#1d1d1f'),
        'text2': rgb('#a1a1a6' if dark else '#6e6e73'),
        'accent': rgb(accent),
        'onAccent': rgb(on_accent),
        'error': rgb(named['red']),
        'success': rgb(named['green']),
        'warning': rgb(named['yellow']),
        # Opaque equivalents of the translucent fills over the window.
        'fill': mix(win, toward, 0.07 if dark else 0.05),
        'fill2': mix(win, toward, 0.12 if dark else 0.09),
        'shade': (0, 0, 0),
        'sep': toward,  # drawn at 10 %, over the art
    }
    p['text3'] = p['text2']
    p['edge'] = mix(p['fill'], toward, 0.135)  # the 0.5 px ring, at 1.5 x
    p['dot'] = p['text']
    p['rule'] = p['fill2']
    p['ruleStrong'] = p['edge']
    p['ink'] = p['accent']
    return p


def check_contrast(p, pairs):
    """Fail rather than ship an unreadable unlock screen."""
    for fg, bg, minimum in pairs:
        ratio = contrast(p[fg], p[bg])
        if ratio < minimum and fg in ('warning', 'success', 'error'):
            # Status colours keep their hue but move toward the text colour
            # until they read; report it so the choice stays visible.
            original, t = p[fg], 0.0
            while contrast(p[fg], p[bg]) < minimum and t < 1:
                t = round(t + 0.05, 2)
                p[fg] = mix(original, p['text'], t)
            print(f'  {fg} moved {t:.0%} toward text for contrast on {bg}', flush=True)
            ratio = contrast(p[fg], p[bg])
        print(f'  contrast {fg:>8} on {bg:<6} {ratio:5.2f}:1 (min {minimum})', flush=True)
        if ratio < minimum:
            sys.exit(f'{fg} on {bg} is {ratio:.2f}:1, below {minimum}:1')


FOLIO_PAIRS = [
    ('text', 'paper', 7.0), ('text2', 'paper', 4.5), ('text3', 'paper', 4.5),
    ('ink', 'paper', 4.5), ('error', 'paper', 4.5), ('success', 'paper', 4.5),
    ('warning', 'paper', 4.5), ('paper', 'ink', 4.5), ('text2', 'sheet', 4.5),
    ('ink', 'well', 3.0),
]
LUMEN_PAIRS = [
    ('text', 'page', 7.0), ('text2', 'page', 4.5), ('error', 'page', 4.5),
    ('success', 'page', 4.5), ('warning', 'page', 4.5), ('accent', 'page', 3.0),
    ('onAccent', 'accent', 4.5), ('text', 'fill2', 7.0), ('dot', 'fill', 7.0),
]


# ------------------------------------------------------------------ drawing kit

class Kit:
    def __init__(self, fonts):
        self.fonts = fonts
        self.layout = ImageFont.Layout.RAQM if features.check('raqm') else ImageFont.Layout.BASIC

    def font(self, face, size):
        path, index = self.fonts[face] if isinstance(self.fonts[face], tuple) else (self.fonts[face], 0)
        return ImageFont.truetype(str(path), size, index=index, layout_engine=self.layout)

    def text(self, s, face, size, color, tracking=0.0):
        """One line of text on a transparent strip as tall as the font's line."""
        font = self.font(face, size)
        ascent, descent = font.getmetrics()
        if tracking:
            advances = [font.getlength(ch) for ch in s]
            width = sum(advances) + tracking * size * (len(s) - 1)
        else:
            width = font.getlength(s)
        img = Image.new('RGBA', (math.ceil(width) + 2, ascent + descent), color + (0,))
        draw = ImageDraw.Draw(img)
        if tracking:
            x = 1.0
            for ch, advance in zip(s, advances):
                draw.text((x, 0), ch, font=font, fill=color + (255,))
                x += advance + tracking * size
        else:
            draw.text((1, 0), s, font=font, fill=color + (255,))
        return img

    def cap(self, s, size, color):
        # Book-plate caption: mono capitals, 0.12 em tracking.
        return self.text(s.upper(), 'mono-medium', size, color, tracking=0.12)

    def display(self, s, face, size, color, tracking, line_height, max_width):
        """A display line with kerning kept and tight tracking, cut to its CSS
        line box (line-height) but never through a glyph. Shrinks to fit."""
        while True:
            font = self.font(face, size)
            stops = [font.getlength(s[:i]) for i in range(len(s) + 1)]
            width = stops[-1] + tracking * size * (len(s) - 1)
            if width <= max_width or size <= 24:
                break
            size = math.floor(size * max_width / width)
        ascent, descent = font.getmetrics()
        pad = math.ceil(size * 0.1)
        img = Image.new('RGBA', (math.ceil(width) + 2 * pad, ascent + descent), color + (0,))
        draw = ImageDraw.Draw(img)
        for i, ch in enumerate(s):
            draw.text((pad + stops[i] + tracking * size * i, 0), ch, font=font, fill=color + (255,))
        top = max(0, round((ascent + descent - line_height * size) / 2))
        ink = img.getbbox() or (0, top, img.width, top + 1)
        bottom = max(top + round(line_height * size), ink[3])
        return img.crop((pad, min(top, ink[1]), img.width - pad + 2, bottom)), size


def icon(name, size, color, stroke=1.6):
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="{size}" height="{size}" '
           f'fill="none" stroke="#{bytes(color).hex()}" stroke-width="{stroke}" stroke-linecap="round" '
           f'stroke-linejoin="round">{ICONS[name]}</svg>')
    png = subprocess.run(['rsvg-convert', '-w', str(size), '-h', str(size)],
                         input=svg.encode(), capture_output=True, check=True).stdout
    return Image.open(io.BytesIO(png)).convert('RGBA')


def row(parts, gap):
    """Lay images side by side, vertically centred."""
    width = sum(p.width for p in parts) + gap * (len(parts) - 1)
    height = max(p.height for p in parts)
    out = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    x = 0
    for part in parts:
        out.alpha_composite(part, (x, (height - part.height) // 2))
        x += part.width + gap
    return out


def rounded(size, radius, fill, corners=(True, True, True, True), edge=None, ss=4):
    """A soft rounded rectangle, supersampled; `edge` is a 1 px inset line."""
    w, h = size
    big = Image.new('RGBA', (w * ss, h * ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(big)
    if edge:
        draw.rounded_rectangle((0, 0, w * ss - 1, h * ss - 1), radius * ss, fill=edge + (255,), corners=corners)
        draw.rounded_rectangle((ss, ss, w * ss - 1 - ss, h * ss - 1 - ss), (radius - 1) * ss,
                               fill=fill, corners=corners)
    else:
        draw.rounded_rectangle((0, 0, w * ss - 1, h * ss - 1), radius * ss, fill=fill, corners=corners)
    return big.resize((w, h), Image.Resampling.LANCZOS)


def disc(diameter, color, ss=8):
    big = Image.new('RGBA', (diameter * ss, diameter * ss), color + (0,))
    ImageDraw.Draw(big).ellipse((0, 0, diameter * ss - 1, diameter * ss - 1), fill=color + (255,))
    return big.resize((diameter, diameter), Image.Resampling.LANCZOS)


def solid(color, alpha=255, size=(4, 4)):
    return Image.new('RGBA', size, color + (alpha,))


def spine(shade, strength, line):
    """The page's shadow on the art (offset -30, blur 60, `shade` at
    `strength`), ending in the page's 1 px hairline (`line`, RGBA)."""
    width = 120
    img = Image.new('RGBA', (width + 1, 4), shade + (0,))
    for x in range(width):
        d = width - x  # distance from the page edge
        a = strength * 0.5 * math.erfc((d - 30) / (30 * math.sqrt(2)))
        for y in range(4):
            img.putpixel((x, y), shade + (round(255 * a),))
    for y in range(4):
        img.putpixel((width, y), line)
    return img


# ------------------------------------------------------------------ art

def print_art(render, source, art, size, ink, paper, moonlit):
    """The plate at the art panel's exact pixel size, one-pixel dither,
    printed in two colours (as azure-folio renders the desktop).

    Dark plates print moonlit, as Folio's plate shader does by default
    (dotfiles/quickshell/folio/shaders/plate.frag): the picture's light
    areas print in ink softened 22 % toward night, a fifth of those dots
    thinned through the same interleaved-gradient threshold, and its shadows
    stay night. A static print is the shader with breathe at zero."""
    focus = list(art.get('desktopFocus', [0.5, 0.5]))
    if art.get('generated'):
        focus[0] = 0.72  # as the lock's portrait crop frames generated plates
    mask = render.desktop_mask(source, {**art, 'desktopFocus': focus}, size)
    w, h = mask.size
    if moonlit:
        light = mask.tobytes()
        lit = bytearray(w * h)  # 0 prints ink, 1 leaves paper
        for y in range(h):
            row_y = y * 0.00583715
            base = y * w
            for x in range(w):
                i = base + x
                if light[i] >= 128:
                    t = 52.9829189 * ((x * 0.06711056 + row_y) % 1.0)
                    lit[i] = 0 if t % 1.0 <= 0.8 else 1
                else:
                    lit[i] = 1
        out = Image.frombytes('P', (w, h), bytes(lit))
        out.putpalette(list(mix(ink, paper, 0.22)) + list(paper))
        return out
    table = bytes(0 if v < 128 else 1 for v in range(256))
    out = Image.frombytes('P', (w, h), mask.tobytes().translate(table))
    out.putpalette(list(ink) + list(paper))
    return out


def sky_lights(looks, mode, pick, style):
    """Plate.qml's `sky`: the field and four lights for a style and mode, in
    the accent's hue and three neighbours leaning toward violet and pink."""
    night = mode == 'dark'
    _, chroma, hue = looks.oklch(looks.derive('lumen', mode, pick)[0])
    c = max(0.12, min(chroma * 1.3, 0.24))
    s = 1 if (hue > 200 or hue < 20) else -1
    haze = style == 'haze'
    if night:
        lums = [0.55, 0.5, 0.6, 0.45] if haze else [0.52, 0.5, 0.56, 0.62]
    else:
        lums = [0.8, 0.78, 0.84, 0.76] if haze else [0.62, 0.6, 0.66, 0.72]
    chroma = c * (0.75 if haze and not night else 1)
    lights = [looks.lch(lums[i], chroma, hue + s * (0, 40, 80, 120)[i]) for i in range(4)]
    # Orbit's night is a touch lighter; by day it lays its light on a fixed grey.
    field = ('#151516' if style == 'orbit' else '#0b0b0e') if night else '#eff0f3'
    return field, lights


def sky(looks, mode, pick, style, size):
    """Lumen's sky (dotfiles/quickshell/folio/shaders/lumen.frag), computed
    per pixel as the shader does: orbit (a tilted ring of light with a soft
    trail), prism (ribbons of light through fluted glass), glow (one soft
    luminous shape) or haze (a full-bleed gradient), each with the shader's
    still film grain. Colours are Qt's: the hex values over 255, mixed as
    they are."""
    import numpy as np

    w, h = size
    night = mode == 'dark'
    field_hex, light_hex = sky_lights(looks, mode, pick, style)
    f32 = np.float32
    field = np.array(rgb(field_hex), f32) / 255
    l0, l1, l2, l3 = (np.array(rgb(x), f32) / 255 for x in light_hex)
    aspect = w / h
    ux = ((np.arange(w, dtype=f32) + 0.5) / w)[None, :]
    uy = ((np.arange(h, dtype=f32) + 0.5) / h)[:, None]

    def smoothstep(e0, e1, x):
        t = np.clip((x - e0) / (e1 - e0), 0, 1)
        return t * t * (3 - 2 * t)

    def mix(a, b, t):
        return a + (b - a) * t

    def tint(color, amount):
        return color[None, None, :] * amount[..., None]

    def expose(light, exposure):
        if night:
            return field + (1 - field) * (1 - np.exp(-light * exposure))
        peak = light.max(axis=-1)
        towards = mix(light / np.maximum(peak, 1e-3)[..., None] * 0.9, 1.0, 0.12)
        return mix(field, towards, ((1 - np.exp(-peak * exposure)) * 0.88)[..., None])

    def ribbons(px, py):
        x = px / aspect
        total = np.zeros(np.broadcast(px, py).shape + (3,), f32)
        for i, tone in enumerate((l0, l1, l2)):
            y = 1.02 - 0.92 * x + 0.06 * np.sin(x * 3.3 + i * 2.3) + (i - 1.0) * 0.085
            wd = 0.045 + 0.018 * i
            d = py - y
            along = 0.35 + 0.65 * (0.5 + 0.5 * np.sin(x * 5.1 + i * 1.9 + 0.6)) ** 1.6
            total += tint(tone, np.exp(-d * d / (2 * wd * wd)) * along * (1.3 - 0.25 * i))
        d3 = py - (1.16 - 0.92 * x)
        total += tint(l3, 0.5 * np.exp(-d3 * d3 / (2 * 0.05 * 0.05)) * smoothstep(0.25, 0.85, x))
        return total

    if style == 'prism':
        px, py = np.broadcast_arrays(ux * aspect, uy)
        # Fluted glass: diagonal bands, each refracting what is behind it.
        ca, sa = math.cos(math.radians(-40)), math.sin(math.radians(-40))
        qx = ca * px + sa * py
        width = 0.2
        band = np.floor(qx / width)
        t = qx / width - band
        vx = (t - 0.5) * width * 1.4
        vy = (t - 0.5) * 0.05 + np.sin(band * 2.7) * 0.02
        light = ribbons(px + ca * vx - sa * vy, py + sa * vx + ca * vy)
        # Each band is lit toward its far edge; the edge catches what is behind it.
        light *= (0.55 + 0.75 * t * t)[..., None]
        light += light * (0.9 * smoothstep(0.95, 1.0, t))[..., None]
        col = expose(light, 1.15 if night else 0.9)
    elif style == 'glow':
        px, py = ux * aspect, uy
        cx, cy = aspect * 0.56, 0.47

        def lobe(dx, dy, k):
            return np.exp(-((px - cx - dx) ** 2) / k) * np.exp(-((py - cy - dy) ** 2) / k)
        f = lobe(-0.15, 0.03, 0.026) + lobe(0.11, -0.07, 0.03) + 0.85 * lobe(0.06, 0.11, 0.02)
        body = smoothstep(0.42, 0.78, f)
        core = smoothstep(0.75, 1.5, f)
        halo = np.exp(-np.hypot(px - cx, py - cy) / 0.2) * (1 - body)
        light = (tint(l1, body * 1.25) + tint(l2, halo * 0.4)
                 + tint(mix(l0, 1.0, 0.7 if night else 0.25), core * 1.5))
        col = expose(light, 1.6 if night else 1.1)
    elif style == 'orbit':
        ca, sa = math.cos(math.radians(-24)), math.sin(math.radians(-24))
        px, py = ux * aspect - aspect * 0.53, uy - 0.52
        qx = (ca * px + sa * py) / 0.27
        qy = (-sa * px + ca * py) / 0.185
        r = np.hypot(qx, qy)
        th = np.arctan2(qy, qx)
        # The edge: brightest low and to the right, gone at the top left.
        side = (0.5 + 0.5 * np.cos(th - math.radians(70))) ** 2.6
        edge = np.exp(-(((r - 1) / (0.012 + 0.05 * (1 - side))) ** 2)) * side
        # The trail: wide haze outside the ring, sweeping up and to the left.
        sweep = (0.5 + 0.5 * np.cos(th - math.radians(235))) ** 1.6
        trail = np.exp(-(((r - 1.18) / 0.32) ** 2)) * sweep * 0.55 + np.exp(-(((r - 1) / 0.12) ** 2)) * 0.12
        light = tint(mix(l0, 1.0, 0.55), edge * 2.2) + tint(mix(l1, 1.0, 0.3), trail)
        base = field if night else np.array([0.80, 0.80, 0.82], f32)
        col = base + (1 - base) * (1 - np.exp(-light * 1.6))
    else:
        warm_deep = l3 * (0.55 if night else 0.8)
        peach = mix(l3, np.array([1.0, 0.82, 0.68], f32), 0.45)
        cool = mix(l0, np.array([0.55, 0.85, 1.0], f32), 0.35)
        x = ux[0][:, None]
        top = mix(warm_deep, l1, smoothstep(0, 0.75, x))
        top = mix(top, l0, smoothstep(0.6, 1.0, x))
        bottom = mix(peach, l2, smoothstep(0, 0.5, x))
        bottom = mix(bottom, cool, smoothstep(0.5, 1.0, x))
        col = mix(top[None], bottom[None], smoothstep(0, 1, uy)[..., None])
        col = col * 0.78 if night else mix(col, 1.0, 0.12)

    # Film grain: fine, still, strongest in the mid-tones, stronger at night.
    # The shader's hash of each (one-pixel) dot, in single precision as the
    # GPU computes it.
    gx, gy = np.broadcast_arrays(np.arange(w, dtype=f32)[None, :] + 17, np.arange(h, dtype=f32)[:, None] + 17)
    p3 = np.stack([gx, gy, gx], axis=-1) * f32(0.1031)
    p3 -= np.floor(p3)
    shifted = p3[..., [1, 2, 0]] + f32(33.33)
    p3 += (p3[..., 0] * shifted[..., 0] + p3[..., 1] * shifted[..., 1] + p3[..., 2] * shifted[..., 2])[..., None]
    noise = (p3[..., 0] + p3[..., 1]) * p3[..., 2]
    noise -= np.floor(noise)
    luma = col[..., 0] * 0.299 + col[..., 1] * 0.587 + col[..., 2] * 0.114
    grain = (noise - 0.5) * (0.075 if night else 0.04)
    col = col + (grain * (0.45 + 0.55 * (1 - np.abs(luma * 2 - 1))))[..., None]
    return Image.fromarray(np.clip(np.rint(col * 255), 0, 255).astype(np.uint8), 'RGB')


def find_face(path, family, style):
    """A face of a font file or collection, by name: (path, index)."""
    for index in range(64):
        try:
            font = ImageFont.truetype(str(path), 12, index=index)
        except OSError:
            break
        if font.getname() == (family, style):
            return path, index
    sys.exit(f'{path} has no {family} {style}')


def find_art(catalog, art_id):
    for collection in catalog['collections']:
        for art in collection['art']:
            if art['id'] == art_id:
                return art
    known = ', '.join(a['id'] for c in catalog['collections'] for a in c['art'])
    sys.exit(f'Unknown Folio art "{art_id}". Known: {known}')


# ------------------------------------------------------------------ the script

# Where the page puts things, per theme, at 1920x1200 (script pixels).
LAYOUT = {
    'folio': {'pad_frac': 0.045, 'pad_max': 72, 'tab_y': 0, 'title_inset': 2, 'rule': 1, 'status_above': 0,
              'dot_first': 32, 'dot_pitch': 30, 'field_right': 24, 'caret_blink': 0, 'go_right': 0,
              'foot_rule': 1, 'foot_bottom': 62},
    'lumen': {'pad_frac': 0.05, 'pad_max': 96, 'tab_y': 39, 'title_inset': 4, 'rule': 0, 'status_above': 1,
              'dot_first': 33, 'dot_pitch': 26, 'field_right': 84, 'caret_blink': 1, 'go_right': 8,
              'foot_rule': 0, 'foot_bottom': 33},
}


def script_header(look, p, sizes):
    def color(name, key=None):
        r, g, b = (round(v / 255, 4) for v in p[key or name])
        return f'pal.{name}.r = {r}; pal.{name}.g = {g}; pal.{name}.b = {b};'
    lines = [
        f'# Generated by build.py: {look["name"]}, {look["theme"]} theme, {look["mode"]}, {look["pick"]}'
        + (f', {look["art"]}.' if look['theme'] == 'folio' else f', {look["sky"]} sky.'),
        f'theme = "{look["theme"]}";',
        # paper: the page; ink: the typed count; text3: systemd's own prompt.
        color('paper', 'page'), color('text'), color('text2'), color('text3'), color('ink', 'dot'),
        color('error'), color('success'),
        f'art_share = {SHARE};',
        f'art_count = {len(sizes)};',
    ]
    lines += [f'lay.{k} = {v};' for k, v in LAYOUT[look['theme']].items()]
    for i, (w, h) in enumerate(sizes):
        lines.append(f'art[{i}].w = {w}; art[{i}].h = {h}; art[{i}].file = "art-{w}x{h}.png";')
    return '\n'.join(lines)


# ------------------------------------------------------------------ the pages

def folio_page(kit, p, name, art, save):
    # Its caption, a sheet on the plate: "Nightfall · Gustave Doré · 1866".
    credit_text = f"{art['title']} · {art.get('credit', '').replace('Azure Folio', 'Folio')}".strip(' ·')
    label = kit.cap(credit_text, 13, p['text2'])
    chip = rounded((label.width + 26, label.height + 14), 10, p['sheet'] + (round(255 * 0.93),))
    chip.alpha_composite(label, (13, 7))
    save(chip, 'credit.png')

    save(spine(p['shade'], 0.12, p['rule'] + (255,)), 'spine.png')

    # The name tab hanging from the page's top edge: ink, paper lettering.
    name_row = row([icon('laptop', 20, p['paper']), kit.text(name, 'ui-medium', 18, p['paper'])], 10)
    tab = rounded((name_row.width + 52, 46), 14, p['ink'] + (255,), corners=(False, False, True, True))
    tab.alpha_composite(name_row, (26, (tab.height - name_row.height) // 2 + 1))
    save(tab, 'tab.png')

    # Caption, title and the lines under the field.
    caps = {'prompt': 'Encrypted disk', 'start': 'Starting up', 'shutdown': 'Shutting down',
            'reboot': 'Restarting', 'update': 'Updating'}
    for key, s in caps.items():
        save(kit.cap(s, 15, p['text2']), f'cap-{key}.png')
    titles = {'prompt': f'Unlock {name}’s disk', 'start': f'Starting {name}',
              'shutdown': f'{name} is shutting down', 'reboot': f'{name} is restarting',
              'update': f'{name} is updating'}
    for key, s in titles.items():
        save(kit.text(s, 'ui-medium', 44, p['text']), f'title-{key}.png')

    save(row([icon('keyboard', 24, p['ink']),
              kit.text('Type the disk passphrase, then press Enter.', 'ui', 21, p['text2'])], 12), 'msg-hint.png')
    save(row([icon('lock', 24, p['ink']),
              kit.text('Checking the passphrase…', 'ui-medium', 21, p['text2'])], 12), 'msg-checking.png')
    save(row([icon('info', 24, p['error']),
              kit.text('That passphrase didn’t unlock the disk. Try again.', 'ui-medium', 21, p['error'])], 12),
         'msg-retry.png')
    save(row([icon('check', 24, p['success']),
              kit.text('Disk unlocked.', 'ui-medium', 21, p['success'])], 12), 'msg-unlocked.png')
    save(row([icon('info', 22, p['warning']),
              kit.text('Caps Lock is on.', 'ui-medium', 19, p['warning'])], 10), 'msg-caps.png')
    save(kit.cap('Esc · boot messages', 14, p['text2']), 'foot-esc.png')

    # The field: a well with a hairline edge, in three slices so it can
    # stretch without bending its corners. Typed characters print as dots.
    field = rounded((64, 72), 16, p['well'] + (255,), edge=p['ruleStrong'])
    save(field.crop((0, 0, 20, 72)), 'field-l.png')
    save(field.crop((31, 0, 33, 72)), 'field-m.png')
    save(field.crop((44, 0, 64, 72)), 'field-r.png')
    save(disc(16, p['ink']), 'dot.png')
    save(disc(10, p['ink']), 'caret.png')
    save(solid(p['ruleStrong']), 'rule.png')
    save(solid(p['rule']), 'rule-soft.png')
    save(solid(p['ink']), 'ink.png')


def lumen_page(kit, p, name, save, content_w):
    # The page's shadow on the sky and its 10 % separator.
    save(spine(p['shade'], 0.16, p['sep'] + (26,)), 'spine.png')

    # A neutral pill at the top: the laptop and the machine's name.
    name_row = row([icon('laptop', 24, p['text']), kit.text(name, 'ui-semibold', 20, p['text'])], 15)
    tab = rounded((name_row.width + 42, 48), 24, p['fill2'] + (255,))
    tab.alpha_composite(name_row, (21, (tab.height - name_row.height) // 2 + 1))
    save(tab, 'tab.png')

    # Sentence-case labels; the title is the action, or the machine's name.
    caps = {'prompt': 'Disk encrypted', 'start': 'Starting up', 'shutdown': 'Shutting down',
            'reboot': 'Restarting', 'update': 'Updating'}
    for key, s in caps.items():
        save(kit.text(s, 'ui-semibold', 17, p['text2']), f'cap-{key}.png')
    titles = {'prompt': 'Unlock', 'start': name, 'shutdown': name, 'reboot': name, 'update': name}
    for key, s in titles.items():
        img, size = kit.display(s, 'ui-bold', 162, p['text'], -0.045, 0.9, content_w)
        if size != 162:
            print(f'  title "{s}" set at {size}px to fit the page', flush=True)
        save(img, f'title-{key}.png')

    # The sentence above the field, then whatever systemd says below it.
    save(kit.text(f'Type {name}’s passphrase to start.', 'ui', 22, p['text2']), 'msg-hint.png')
    save(kit.text('Checking the passphrase…', 'ui', 22, p['text2']), 'msg-checking.png')
    save(kit.text('That passphrase didn’t unlock the disk. Try again.', 'ui-medium', 22, p['error']), 'msg-retry.png')
    save(kit.text('Disk unlocked.', 'ui-medium', 22, p['success']), 'msg-unlocked.png')
    save(kit.text('Caps Lock is on.', 'ui-medium', 19, p['warning']), 'msg-caps.png')
    save(kit.text('US keyboard · Esc shows the boot messages', 'ui', 19, p['text2']), 'foot-esc.png')

    # The field: a pill with a fine ring, dots in the text color, an accent
    # caret and a round accent button with an arrow at its end.
    field = rounded((80, 68), 34, p['fill'] + (255,), edge=p['edge'])
    save(field.crop((0, 0, 36, 68)), 'field-l.png')
    save(field.crop((39, 0, 41, 68)), 'field-m.png')
    save(field.crop((44, 0, 80, 68)), 'field-r.png')
    go = disc(54, p['accent'])
    go.alpha_composite(icon('right', 24, p['onAccent'], stroke=2.2), (15, 15))
    save(go, 'go.png')
    save(disc(12, p['dot']), 'dot.png')
    save(rounded((3, 33), 1, p['accent'] + (255,)), 'caret.png')
    save(solid(p['ruleStrong']), 'rule.png')
    save(solid(p['rule']), 'rule-soft.png')
    save(solid(p['accent']), 'ink.png')


def build(*, looks, render, assets, template, out, name, theme, mode, pick, art_id, sizes,
          bold_font, theme_name, install_dir=None, sky_style='orbit'):
    """Print the theme for one look into `out`. Plymouth finds its images and
    script at `install_dir` (where `out` will be at boot; default: `out`)."""
    if (theme not in looks.THEMES or mode not in looks.MODES or not looks.valid_pick(theme, pick)
            or sky_style not in looks.SKIES):
        sys.exit(f'Unknown look: {theme} {mode} {pick} {sky_style}')
    catalog = json.loads((assets / 'catalog.json').read_text())
    art = find_art(catalog, art_id) if theme == 'folio' else None
    p = folio_palette(looks, mode, pick) if theme == 'folio' else lumen_palette(looks, mode, pick)
    print(f'Interstellar boot · {name} · {theme} · {mode} · {pick} · ' + (art_id if art else sky_style), flush=True)
    check_contrast(p, FOLIO_PAIRS if theme == 'folio' else LUMEN_PAIRS)

    fonts = assets / 'fonts'
    kit = Kit({
        'mono': fonts / 'font-0.ttf', 'mono-medium': fonts / 'font-1.ttf',
        'ui': fonts / 'font-2.ttf', 'ui-medium': fonts / 'font-3.ttf', 'ui-semibold': fonts / 'font-4.ttf',
        'hero': fonts / 'font-5.ttf', 'ui-bold': find_face(bold_font, 'Inter', 'Bold'),
    })
    out.mkdir(parents=True, exist_ok=True)

    def save(img, file):
        img.save(out / file, optimize=True)

    # The art, at each screen size it may meet.
    for w, h in sizes:
        panel = (round(w * SHARE), h)
        if theme == 'folio':
            img = print_art(render, assets / 'sources' / art['file'], art, panel,
                            p['ink'], p['paper'], moonlit=mode == 'dark')
        else:
            img = sky(looks, mode, pick, sky_style, panel)
        save(img, f'art-{w}x{h}.png')
        print(f'  printed {art["id"] if art else sky_style} for {w}x{h}', flush=True)

    layout = LAYOUT[theme]
    if theme == 'folio':
        folio_page(kit, p, name, art, save)
    else:
        content_w = round(1920 * (1 - SHARE)) - 2 * layout['pad_max']
        lumen_page(kit, p, name, save, content_w)

    if '#@GENERATED@' not in template:
        sys.exit('interstellar.script lost its #@GENERATED@ marker')
    look = {'name': name, 'theme': theme, 'mode': mode, 'pick': pick, 'art': art_id, 'sky': sky_style}
    (out / f'{theme_name}.script').write_text(template.replace('#@GENERATED@', script_header(look, p, sizes)))

    where = install_dir or out
    # Plymouth reads these as 0xRRGGBBAA: six digits would be a nearly
    # transparent, wrongly tinted text in the boot messages behind Esc.
    hexa = lambda c: '0x' + bytes(c).hex() + 'ff'  # noqa: E731
    desc = f'{theme}, {mode}, {pick}, ' + (art_id if art else sky_style)
    (out / f'{theme_name}.plymouth').write_text(f"""[Plymouth Theme]
Name=Interstellar
Description=Interstellar's boot and disk-unlock screen ({desc})
ModuleName=script

[script]
ImageDir={where}
ScriptFile={where}/{theme_name}.script
MonospaceFont=IBM Plex Mono 17px
ConsoleLogTextColor={hexa(p['text'])}
ConsoleLogBackgroundColor={hexa(p['page'])}
""")


def parse_sizes(specs):
    sizes = []
    for spec in specs:
        w, h = (int(v) for v in spec.lower().split('x'))
        if not (320 <= w <= 8192 and 240 <= h <= 8192):
            sys.exit(f'Unsupported screen size {spec}')
        sizes.append((w, h))
    return sizes


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--assets', type=Path, required=True, help='assets/azure-folio')
    parser.add_argument('--render', type=Path, required=True, help='tools/azure-folio/render.py')
    parser.add_argument('--looks', type=Path, required=True, help='tools/azure-folio/looks.py')
    parser.add_argument('--script', type=Path, required=True, help='interstellar.script template')
    parser.add_argument('--bold-font', type=Path, required=True, help='a font file or collection with Inter Bold')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--theme-name', default='interstellar')
    parser.add_argument('--install-dir', help='where the theme lives at boot (default: --out)')
    parser.add_argument('--name', required=True)
    parser.add_argument('--theme', choices=['folio', 'lumen'], required=True)
    parser.add_argument('--mode', choices=['light', 'dark'], required=True)
    parser.add_argument('--pick', required=True, help="the theme's color: a name from its set, or #rrggbb")
    parser.add_argument('--art', required=True, help="Folio's plate, by catalog id")
    parser.add_argument('--sky', default='orbit', help="Lumen's sky: orbit, prism, glow or haze")
    parser.add_argument('--size', action='append', required=True, help='WIDTHxHEIGHT')
    args = parser.parse_args()
    build(looks=load_module('looks', args.looks), render=load_module('render', args.render),
          assets=args.assets, template=args.script.read_text(), out=args.out, name=args.name,
          theme=args.theme, mode=args.mode, pick=args.pick, art_id=args.art, sizes=parse_sizes(args.size),
          bold_font=args.bold_font, theme_name=args.theme_name, install_dir=args.install_dir,
          sky_style=args.sky)


if __name__ == '__main__':
    main()
