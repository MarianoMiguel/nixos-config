#!/usr/bin/env python3
"""Print Interstellar's Plymouth theme: the art on the left, the page on the right.

One look is a theme (Folio or Lumen), a mode and one color, resolved by
tools/azure-folio/looks.py exactly as the desktop resolves it. Folio prints
its plate in the derived ink beside a paper page; Lumen shows a nebula in
hues around its accent beside a plain page in the window color.

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

from PIL import Image, ImageDraw, ImageFont, ImageMath, features

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


def mulberry32(seed):
    """The study's star generator (rand() in v1.html), bit for bit."""
    state = [seed & 0xffffffff]

    def imul(a, b):
        return (a * b) & 0xffffffff

    def nxt():
        state[0] = (state[0] + 0x6d2b79f5) & 0xffffffff
        s = state[0]
        t = imul(s ^ (s >> 15), 1 | s)
        t = ((t + imul(t ^ (t >> 7), 61 | t)) & 0xffffffff) ^ t
        return ((t ^ (t >> 14)) & 0xffffffff) / 4294967296
    return nxt


def bayer(x, y, levels=3):
    """The ordered-dither (Bayer) matrix of side 2**levels at x, y: each
    finer 2x2 level [[0, 2], [3, 1]] is the more significant digit."""
    v = 0
    for i in range(levels):
        xb, yb = (x >> i) & 1, (y >> i) & 1
        v = v * 4 + (((xb ^ yb) << 1) | yb)
    return v


def nebula(looks, mode, accent, size):
    """Lumen's wallpaper: soft glows in hues around the accent over a sky;
    deep space with fine stars at night, a pale haze by day.

    Each glow is a gaussian (sigma 0.42 of its radius, in widths) composited
    as straight color: col = mix(col, glow, alpha * g). Matches the shell."""
    w, h = size
    dark = mode == 'dark'
    _, chroma, hue = looks.oklch(accent)
    c = max(0.06, min(chroma, 0.16))
    sky = (rgb('#0a0b12'), rgb('#141420')) if dark else (rgb('#eef0f6'), rgb('#f8f7fb'))
    glows = [(0.22, 0.34, 0.42), (0.78, 0.58, 0.38), (0.52, 1.02, 0.46), (0.92, 0.08, 0.22)]
    if dark:
        offsets, alphas = (0, 46, -52, 90), (0.9, 0.75, 0.7, 0.45)
        tone = lambda dh: looks.lch(0.42, c, hue + dh)  # noqa: E731
    else:
        offsets, alphas = (0, 40, -48, 24), (0.85, 0.7, 0.65, 0.4)
        tone = lambda dh: looks.lch(0.87, min(c, 0.11), hue + dh)  # noqa: E731

    def column(values):
        img = Image.new('F', (1, h))
        img.putdata(values)
        return img.resize((w, h), Image.Resampling.NEAREST)

    def line(values):
        img = Image.new('F', (w, 1))
        img.putdata(values)
        return img.resize((w, h), Image.Resampling.NEAREST)

    # The sky, per channel, as floats so the glows don't band before the end.
    bands = [column([a + (b - a) * (y + 0.5) / h for y in range(h)]) for a, b in zip(*sky)]
    for (gx, gy, r), dh, alpha in zip(glows, offsets, alphas):
        color = rgb(tone(dh))
        sigma = 0.42 * r * w
        cx, cy = gx * w, gy * h
        fx = line([math.exp(-((x + 0.5 - cx) ** 2) / (2 * sigma * sigma)) for x in range(w)])
        fy = column([alpha * math.exp(-((y + 0.5 - cy) ** 2) / (2 * sigma * sigma)) for y in range(h)])
        weight = ImageMath.lambda_eval(lambda a: a['x'] * a['y'], x=fx, y=fy)
        bands = [ImageMath.lambda_eval(lambda a: a['c'] + (a['g'] - a['c']) * a['k'], c=band, g=float(g), k=weight)
                 for band, g in zip(bands, color)]
    # Down to 8 bits through an 8x8 Bayer threshold (converting truncates, so
    # floor(c + t) averages to c): a pale haze moves a few levels across
    # hundreds of pixels and would otherwise show contour rings.
    n = 8
    tile = Image.new('F', (n, n))
    tile.putdata([(bayer(x, y) + 0.5) / (n * n) for y in range(n) for x in range(n)])
    strip = Image.new('F', (w, n))
    for x in range(0, w, n):
        strip.paste(tile, (x, 0))
    threshold = Image.new('F', (w, h))
    for y in range(0, h, n):
        threshold.paste(strip, (0, y))
    out = Image.merge('RGB', [ImageMath.lambda_eval(lambda a: a['c'] + a['t'], c=b, t=threshold).convert('L')
                              for b in bands])
    if dark:
        # 180 stars as the study draws them on its 0.75-scale canvas of the
        # 1280 x 800 mock's art (538 px wide); positions are fractions.
        k, ss = w / 538, 8
        r = mulberry32(7)
        for _ in range(180):
            a = 0.12 + r() * 0.5
            s = (0.55 if r() < 0.94 else 1.1) * k
            x, y = r() * w, r() * h
            box = math.ceil(s) + 2
            # The disc drawn 8x larger at its sub-pixel spot, then averaged
            # down to an antialiased mask; white is blended through it.
            patch = Image.new('L', (2 * box * ss, 2 * box * ss), 0)
            ox, oy = (box + x % 1) * ss, (box + y % 1) * ss
            ImageDraw.Draw(patch).ellipse((ox - s * ss, oy - s * ss, ox + s * ss, oy + s * ss),
                                          fill=round(255 * a))
            patch = patch.resize((2 * box, 2 * box), Image.Resampling.BOX)
            out.paste((255, 255, 255), (math.floor(x) - box, math.floor(y) - box,
                                        math.floor(x) + box, math.floor(y) + box), patch)
    return out


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
        + (f', {look["art"]}.' if look['theme'] == 'folio' else '.'),
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
    # The page's shadow on the nebula and its 10 % separator.
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
          bold_font, theme_name, install_dir=None):
    """Print the theme for one look into `out`. Plymouth finds its images and
    script at `install_dir` (where `out` will be at boot; default: `out`)."""
    if theme not in looks.THEMES or mode not in looks.MODES or not looks.valid_pick(theme, pick):
        sys.exit(f'Unknown look: {theme} {mode} {pick}')
    catalog = json.loads((assets / 'catalog.json').read_text())
    art = find_art(catalog, art_id) if theme == 'folio' else None
    p = folio_palette(looks, mode, pick) if theme == 'folio' else lumen_palette(looks, mode, pick)
    print(f'Interstellar boot · {name} · {theme} · {mode} · {pick}' + (f' · {art_id}' if art else ''), flush=True)
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
            img = nebula(looks, mode, looks.to_hex(v / 255 for v in p['accent']), panel)
        save(img, f'art-{w}x{h}.png')
        print(f'  printed {art["id"] if art else "nebula"} for {w}x{h}', flush=True)

    layout = LAYOUT[theme]
    if theme == 'folio':
        folio_page(kit, p, name, art, save)
    else:
        content_w = round(1920 * (1 - SHARE)) - 2 * layout['pad_max']
        lumen_page(kit, p, name, save, content_w)

    if '#@GENERATED@' not in template:
        sys.exit('interstellar.script lost its #@GENERATED@ marker')
    look = {'name': name, 'theme': theme, 'mode': mode, 'pick': pick, 'art': art_id}
    (out / f'{theme_name}.script').write_text(template.replace('#@GENERATED@', script_header(look, p, sizes)))

    where = install_dir or out
    hexa = lambda c: '0x' + bytes(c).hex()  # noqa: E731
    desc = f'{theme}, {mode}, {pick}' + (f', {art_id}' if art else '')
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
    parser.add_argument('--size', action='append', required=True, help='WIDTHxHEIGHT')
    args = parser.parse_args()
    build(looks=load_module('looks', args.looks), render=load_module('render', args.render),
          assets=args.assets, template=args.script.read_text(), out=args.out, name=args.name,
          theme=args.theme, mode=args.mode, pick=args.pick, art_id=args.art, sizes=parse_sizes(args.size),
          bold_font=args.bold_font, theme_name=args.theme_name, install_dir=args.install_dir)


if __name__ == '__main__':
    main()
