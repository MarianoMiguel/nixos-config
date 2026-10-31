#!/usr/bin/env python3
"""Interstellar's looks: a theme, a mode and one color.

Folio prints in ink on paper; Lumen is neutral grays and glass. Each theme
takes one color, a named one from its own set or any #rrggbb. Its hue is
kept and its lightness moves until it reads (derive), so no pick can make the
desktop unreadable. Everything else in a palette belongs to the theme.

The shell runs the same rules in dotfiles/quickshell/folio/Common/Looks.js;
test_looks.py keeps the two equal.
"""
import argparse
import json
import math
import re
import shutil
import sys
from pathlib import Path

THEMES = ('folio', 'lumen')
MODES = ('light', 'dark')
HEX = re.compile(r'^#[0-9a-fA-F]{6}$')

# Folio's inks: (light, dark), as tools/azure-folio's catalog has them.
INKS = {'azure': ('#214c94', '#adc7ed'), 'cobalt': ('#244fb8', '#9dbbfa'), 'slate': ('#35556e', '#adc3d2')}
# Lumen's colors, as picked; derive() fits each to the mode.
ACCENTS = {'blue': '#0a7aff', 'purple': '#a050e8', 'pink': '#ef4f97', 'red': '#f2453a', 'orange': '#ff8a00',
           'yellow': '#ffc800', 'green': '#30c35a', 'teal': '#2bb3c8', 'graphite': '#8a8a90'}
NAMED = {'folio': INKS, 'lumen': ACCENTS}
DEFAULT = {'folio': 'azure', 'lumen': 'blue'}
# The window, the terminal and Chrome's frame.
BACKGROUND = {'folio': {'light': '#f7f4e9', 'dark': '#101d33'}, 'lumen': {'light': '#ffffff', 'dark': '#1e1e20'}}
# Text on a Lumen accent when white would not read.
INK_ON_LIGHT = '#1d1d1f'


def valid_pick(theme, pick):
    return theme in THEMES and isinstance(pick, str) and (pick in NAMED[theme] or bool(HEX.fullmatch(pick)))


# ------------------------------------------------------------------ color

def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _gam(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def rgb(h):
    return [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]


def to_hex(v):
    return '#' + ''.join(f'{round(min(1, max(0, x)) * 255):02x}' for x in v)


def oklch(h):
    r, g, b = (_lin(x) for x in rgb(h))
    l = math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m = math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    s = math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s
    A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
    B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
    return L, math.hypot(A, B), (math.degrees(math.atan2(B, A)) + 360) % 360


def _linear(L, C, h):
    A, B = C * math.cos(math.radians(h)), C * math.sin(math.radians(h))
    l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3
    m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3
    s = (L - 0.0894841775 * A - 1.291485548 * B) ** 3
    return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s]


def lch(L, C, h):
    """OKLCH to sRGB hex, giving up chroma (never hue or lightness) to stay in gamut."""
    c, v = C, _linear(L, C, h)
    while c > 0 and any(x < -1e-4 or x > 1 + 1e-4 for x in v):
        c -= 0.004
        v = _linear(L, max(0, c), h)
    return to_hex(_gam(min(1, max(0, x))) for x in v)


def luminance(h):
    r, g, b = (_lin(x) for x in rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    x, y = luminance(a), luminance(b)
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)


def mix(a, b, t):
    return to_hex(x + (y - x) * t for x, y in zip(rgb(a), rgb(b)))


# ------------------------------------------------------------------ looks

def derive(theme, mode, pick):
    """The color a theme shows for a pick in a mode, and the text that goes on it.

    Folio's ink carries plates and text on paper (7:1) and at night (9:1,
    softened). Lumen's accent stands out from the window (3:1) and carries
    white text, or near-black where white would cost too much lightness.
    """
    if not valid_pick(theme, pick) or mode not in MODES:
        raise ValueError(f'Unknown look: {theme} {mode} {pick}')
    bg = BACKGROUND[theme][mode]
    if theme == 'folio' and pick in INKS:
        return INKS[pick][0 if mode == 'light' else 1], bg
    pick = (ACCENTS[pick] if theme == 'lumen' and pick in ACCENTS else pick).lower()
    L0, C0, h = oklch(pick)
    C = (min(C0, 0.16) if mode == 'light' else min(C0 * 0.55, 0.08)) if theme == 'folio' else C0
    best = None
    for i in range(155):
        L = 0.2 + i * 0.005
        c = lch(L, C, h)
        cost = abs(L - L0)
        if theme == 'folio':
            if contrast(c, bg) < (7 if mode == 'light' else 9):
                continue
            on = bg
        else:
            if contrast(c, bg) < 3:
                continue
            if contrast('#ffffff', c) >= 4.5:
                on = '#ffffff'
            elif contrast(INK_ON_LIGHT, c) >= 4.5:
                on = INK_ON_LIGHT
                cost += 0.1
            else:
                continue
        if best is None or cost < best[0]:
            best = (cost, c, on)
    return (best[1], best[2]) if best else (pick, bg if theme == 'folio' else '#ffffff')


def colors(theme, mode, pick):
    """A whole palette, in Omarchy's colors.toml keys, for themeport."""
    accent = derive(theme, mode, pick)[0]
    light = mode == 'light'
    if theme == 'folio':
        # Paper and night; the ink is the accent and the terminal's blue.
        p = {'background': '#f7f4e9' if light else '#101d33', 'foreground': '#263a57' if light else '#e4e9f0',
             'lighter_background': '#fbf9f2' if light else '#16253c', 'dark_background': '#eee9dd' if light else '#101b2c',
             'darker_background': '#e3dccf' if light else '#0b1424', 'dark_foreground': '#536177' if light else '#9eb0ca',
             'bright_foreground': accent if light else '#f7f4e9', 'muted': '#536177' if light else '#9eb0ca',
             'selection': '#d9d0bf' if light else '#263e5e',
             'red': '#a44747' if light else '#e9a5a0', 'green': '#367061' if light else '#a1caba',
             'yellow': '#82651e' if light else '#d9c28e', 'orange': '#8e5e35' if light else '#dbb191',
             'cyan': '#356c82' if light else '#9fc8d8', 'magenta': '#6d6089' if light else '#c5b5df', 'blue': accent}
    else:
        # Neutral grays; terminal colors that read on white and on graphite.
        p = {'background': '#ffffff' if light else '#1e1e20', 'foreground': '#1d1d1f' if light else '#f5f5f7',
             'lighter_background': '#f5f5f7' if light else '#2c2c2e', 'dark_background': '#f2f2f5' if light else '#252527',
             'darker_background': '#e8e8ed' if light else '#161618', 'dark_foreground': '#6e6e73' if light else '#a1a1a6',
             'bright_foreground': '#000000' if light else '#ffffff', 'muted': '#86868b' if light else '#8e8e93',
             'selection': mix(accent, '#ffffff', 0.72) if light else mix(accent, '#1e1e20', 0.55),
             'red': '#c4281c' if light else '#ff6961', 'green': '#1e7d36' if light else '#5fd068',
             'yellow': '#8f6400' if light else '#ffd60a', 'orange': '#b25000' if light else '#ffa24c',
             'cyan': '#0b7285' if light else '#64d2ff', 'magenta': '#9d36c7' if light else '#da8fff',
             'blue': '#0b5fcc' if light else '#5aa9ff'}
    # The window's lights (close, maximize) and their quiet unfocused grey.
    if theme == 'folio':
        p.update({'light_close': '#b4473f' if light else '#f09088', 'light_zoom': '#3f7d5c' if light else '#8cc5a3',
                  'light_idle': '#d9d0bf' if light else '#263e5e'})
    else:
        p.update({'light_close': '#ff5f57', 'light_zoom': '#28c840', 'light_idle': '#d1d1d6' if light else '#48484a'})
    return {'mode': mode, **p, 'accent': accent}


def resolve(theme, mode, pick):
    """Everything the greeter and the boot screen need, for both modes."""
    out = {'theme': theme, 'mode': mode, 'pick': pick}
    for m in MODES:
        accent, on = derive(theme, m, pick)
        out[m] = {'accent': accent, 'onAccent': on, 'background': BACKGROUND[theme][m]}
    return out


def write_themeport(theme, mode, pick, out):
    """Generated themeport themes for a look: interstellar-<theme>-<mode>, both modes."""
    out = Path(out)
    for m in MODES:
        d = out / f'interstellar-{theme}-{m}'
        if d.exists():
            shutil.rmtree(d)
        d.mkdir(parents=True)
        (d / 'colors.toml').write_text(''.join(f'{k} = "{v}"\n' for k, v in colors(theme, m, pick).items()))


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest='command', required=True)
    for name in ('derive', 'themeport'):
        s = sub.add_parser(name)
        s.add_argument('--theme', choices=THEMES, required=True)
        s.add_argument('--mode', choices=MODES, required=True)
        s.add_argument('--pick', required=True)
        if name == 'themeport':
            s.add_argument('--out', required=True)
    args = p.parse_args()
    if not valid_pick(args.theme, args.pick):
        sys.exit(f'Unknown {args.theme} color: {args.pick}')
    if args.command == 'derive':
        print(json.dumps(resolve(args.theme, args.mode, args.pick)))
    else:
        write_themeport(args.theme, args.mode, args.pick, args.out)


if __name__ == '__main__':
    main()
