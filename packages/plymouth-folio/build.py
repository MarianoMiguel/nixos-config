#!/usr/bin/env python3
"""Print Folio's Plymouth theme: the plate on the left, the page on the right.

Everything static is drawn here, at build time, with Folio's own fonts,
icons and palette, so the disk-unlock screen does not depend on font
rendering inside the initrd. Plymouth only places these images and renders
the few strings that arrive at boot (systemd's prompt, messages, the unit
being started). The page is drawn for 1920x1200, Bonhart's panel and its
firmware console; the art is printed at every listed screen size.
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

# Folio icons (workshop/studies/_kit/folio.js): 24-unit grid, 1.6 stroke.
ICONS = {
    'laptop': '<rect x="5" y="5" width="14" height="10" rx="1.6"/><path d="M2.5 18.5h19"/>',
    'lock': '<rect x="5" y="10.5" width="14" height="10" rx="2.5"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/>',
    'keyboard': '<rect x="2.5" y="6" width="19" height="12" rx="2.2"/>'
                '<path d="M6.5 10h.01M10 10h.01M14 10h.01M17.5 10h.01M7.5 14h9"/>',
    'check': '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
    'info': '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.5M12 7.6v.01"/>',
}


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


def palette(catalog, mode, ink):
    """Folio's tokens (dotfiles/quickshell/folio/Common/Theme.qml).

    Secondary text uses Folio's higher-contrast setting: this screen is read
    through the KVM's compressed video capture as often as on the panel.
    """
    dark = mode == 'dark'
    p = {
        'paper': rgb('#101d33' if dark else '#f7f4e9'),
        'text': rgb('#e4e9f0' if dark else '#1a2740'),
        'ink': rgb(catalog['inks'][ink][mode]),
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
    return p


def check_contrast(p):
    """Fail the build rather than ship an unreadable unlock screen."""
    pairs = [
        ('text', 'paper', 7.0), ('text2', 'paper', 4.5), ('text3', 'paper', 4.5),
        ('ink', 'paper', 4.5), ('error', 'paper', 4.5), ('success', 'paper', 4.5),
        ('warning', 'paper', 4.5), ('paper', 'ink', 4.5), ('text2', 'sheet', 4.5),
        ('ink', 'well', 3.0),
    ]
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


class Kit:
    def __init__(self, fonts):
        self.fonts = fonts
        self.layout = ImageFont.Layout.RAQM if features.check('raqm') else ImageFont.Layout.BASIC

    def font(self, face, size):
        return ImageFont.truetype(str(self.fonts[face]), size, layout_engine=self.layout)

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


def icon(name, size, color):
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="{size}" height="{size}" '
           f'fill="none" stroke="#{bytes(color).hex()}" stroke-width="1.6" stroke-linecap="round" '
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


def spine(p):
    """The page's shadow on the art (offset -30, blur 60, shade at 12 %),
    ending in the page's 1 px hairline."""
    width = 120
    img = Image.new('RGBA', (width + 1, 4), p['shade'] + (0,))
    for x in range(width):
        d = width - x  # distance from the page edge
        a = 0.12 * 0.5 * math.erfc((d - 30) / (30 * math.sqrt(2)))
        for y in range(4):
            img.putpixel((x, y), p['shade'] + (round(255 * a),))
    for y in range(4):
        img.putpixel((width, y), p['rule'] + (255,))
    return img


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


def find_art(catalog, art_id):
    for collection in catalog['collections']:
        for art in collection['art']:
            if art['id'] == art_id:
                return art
    known = ', '.join(a['id'] for c in catalog['collections'] for a in c['art'])
    sys.exit(f'Unknown Folio art "{art_id}". Known: {known}')


def script_header(args, p, sizes):
    def color(name):
        r, g, b = (round(v / 255, 4) for v in p[name])
        return f'pal.{name}.r = {r}; pal.{name}.g = {g}; pal.{name}.b = {b};'
    lines = [
        f'# Generated by build.py: {args.name}, {args.mode} paper, {args.ink} ink, {args.art}.',
        *(color(n) for n in ('paper', 'text', 'text2', 'text3', 'ink', 'error', 'success')),
        f'art_share = {SHARE};',
        f'art_count = {len(sizes)};',
    ]
    for i, (w, h) in enumerate(sizes):
        lines.append(f'art[{i}].w = {w}; art[{i}].h = {h}; art[{i}].file = "art-{w}x{h}.png";')
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets', type=Path, required=True, help='assets/azure-folio')
    parser.add_argument('--render', type=Path, required=True, help='tools/azure-folio/render.py')
    parser.add_argument('--script', type=Path, required=True, help='folio.script template')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--name', required=True)
    parser.add_argument('--mode', choices=['light', 'dark'], required=True)
    parser.add_argument('--ink', required=True)
    parser.add_argument('--art', required=True)
    parser.add_argument('--size', action='append', required=True, help='WIDTHxHEIGHT')
    args = parser.parse_args()

    # The desktop's own renderer, so the plate is printed exactly as the
    # wallpaper is (tools/azure-folio/render.py).
    spec = importlib.util.spec_from_file_location('render', args.render)
    render = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(render)

    catalog = json.loads((args.assets / 'catalog.json').read_text())
    if args.ink not in catalog['inks']:
        sys.exit(f'Unknown Folio ink "{args.ink}". Known: {", ".join(catalog["inks"])}')
    art = find_art(catalog, args.art)
    p = palette(catalog, args.mode, args.ink)
    print(f'Folio boot · {args.name} · {args.mode} · {args.ink} · {args.art}', flush=True)
    check_contrast(p)

    fonts = args.assets / 'fonts'
    kit = Kit({
        'mono': fonts / 'font-0.ttf', 'mono-medium': fonts / 'font-1.ttf',
        'ui': fonts / 'font-2.ttf', 'ui-medium': fonts / 'font-3.ttf', 'ui-semibold': fonts / 'font-4.ttf',
        'hero': fonts / 'font-5.ttf',
    })
    out = args.out
    out.mkdir(parents=True, exist_ok=True)

    def save(img, name):
        img.save(out / name, optimize=True)

    # The plate, at each screen size it may meet.
    sizes = []
    for spec in args.size:
        w, h = (int(v) for v in spec.lower().split('x'))
        sizes.append((w, h))
        save(print_art(render, args.assets / 'sources' / art['file'], art, (round(w * SHARE), h),
                       p['ink'], p['paper'], moonlit=args.mode == 'dark'), f'art-{w}x{h}.png')
        print(f'  printed {art["id"]} for {w}x{h}', flush=True)

    # Its caption, a sheet on the plate: "Nightfall · Gustave Doré · 1866".
    credit_text = f"{art['title']} · {art.get('credit', '').replace('Azure Folio', 'Folio')}".strip(' ·')
    label = kit.cap(credit_text, 13, p['text2'])
    chip = rounded((label.width + 26, label.height + 14), 10, p['sheet'] + (round(255 * 0.93),))
    chip.alpha_composite(label, (13, 7))
    save(chip, 'credit.png')

    save(spine(p), 'spine.png')

    # The name tab hanging from the page's top edge: ink, paper lettering.
    name_row = row([icon('laptop', 20, p['paper']), kit.text(args.name, 'ui-medium', 18, p['paper'])], 10)
    tab = rounded((name_row.width + 52, 46), 14, p['ink'] + (255,), corners=(False, False, True, True))
    tab.alpha_composite(name_row, (26, (tab.height - name_row.height) // 2 + 1))
    save(tab, 'tab.png')

    # Caption, title and the lines under the field.
    caps = {'prompt': 'Encrypted disk', 'start': 'Starting up', 'shutdown': 'Shutting down',
            'reboot': 'Restarting', 'update': 'Updating'}
    for key, s in caps.items():
        save(kit.cap(s, 15, p['text2']), f'cap-{key}.png')
    titles = {'prompt': f'Unlock {args.name}’s disk', 'start': f'Starting {args.name}',
              'shutdown': f'{args.name} is shutting down', 'reboot': f'{args.name} is restarting',
              'update': f'{args.name} is updating'}
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

    template = args.script.read_text()
    if '#@GENERATED@' not in template:
        sys.exit('folio.script lost its #@GENERATED@ marker')
    (out / 'folio.script').write_text(template.replace('#@GENERATED@', script_header(args, p, sizes)))

    hexa = lambda c: '0x' + bytes(c).hex()  # noqa: E731
    (out / 'folio.plymouth').write_text(f"""[Plymouth Theme]
Name=Folio
Description=Folio's boot and disk-unlock screen: the plate and the page ({args.mode}, {args.ink}, {args.art})
ModuleName=script

[script]
ImageDir={out}
ScriptFile={out}/folio.script
MonospaceFont=IBM Plex Mono 17px
ConsoleLogTextColor={hexa(p['text'])}
ConsoleLogBackgroundColor={hexa(p['paper'])}
""")


if __name__ == '__main__':
    main()
