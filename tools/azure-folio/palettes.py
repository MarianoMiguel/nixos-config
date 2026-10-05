#!/usr/bin/env python3
"""Build Folio UI palettes independently of the immutable artwork."""
import json
import sys
from pathlib import Path


def palette(ink, mode):
    light=mode=='light'
    p={'mode':mode,'background':'#f7f4e9' if light else '#101d33',
       'foreground':'#263a57' if light else '#e4e9f0','accent':ink,'blue':ink,
       'lighter_background':'#fbf9f2' if light else '#16253c',
       'dark_background':'#eee9dd' if light else '#101b2c',
       'darker_background':'#e3dccf' if light else '#0b1424',
       'dark_foreground':'#536177' if light else '#9eb0ca',
       'bright_foreground':'#214c94' if light else '#f7f4e9',
       'muted':'#536177' if light else '#9eb0ca',
       'selection':'#d9d0bf' if light else '#263e5e',
       'red':'#a44747' if light else '#e9a5a0',
       'green':'#367061' if light else '#a1caba',
       'yellow':'#82651e' if light else '#d9c28e',
       'orange':'#8e5e35' if light else '#dbb191',
       'cyan':'#356c82' if light else '#9fc8d8',
       'magenta':'#6d6089' if light else '#c5b5df'}
    return p



def build(src, out):
    catalog = json.loads((src / 'catalog.json').read_text())
    for ink, colors in catalog['inks'].items():
        for mode, color in colors.items():
            dest = out / f'folio-{ink}-{mode}'
            dest.mkdir(parents=True)
            (dest / 'colors.toml').write_text(''.join(
                f'{key} = "{value}"\n' for key, value in palette(color, mode).items()))


if __name__ == '__main__':
    build(Path(sys.argv[1]), Path(sys.argv[2]))
